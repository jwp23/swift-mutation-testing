struct FallbackExecutor: Sendable {
    let deps: ExecutionDeps
    let configuration: RunnerConfiguration

    /// Tests the given mutants from a build of their own file, one file at a time. The mutants are
    /// passed in rather than read back off the input: a run reaches the fallback with some of its
    /// mutants already routed elsewhere, and testing those here would report them a second time.
    func execute(
        input: RunnerInput,
        mutants: [MutantDescriptor],
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for file in input.schematizedFiles {
            results += try await processFile(file: file, mutants: mutants, input: input, pool: pool)
        }

        return results
    }

    private func processFile(
        file: SchematizedFile,
        mutants: [MutantDescriptor],
        input: RunnerInput,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        let fileMutants = mutants.filter { $0.filePath == file.originalPath && $0.isSchematizable }

        guard !fileMutants.isEmpty else { return [] }

        if let cached = await cachedResults(for: fileMutants) {
            return cached
        }

        let sandbox = try await SandboxFactory().create(
            projectPath: input.projectPath,
            schematizedFiles: [file],
            supportFileContent: input.supportFileContent
        )

        await deps.reporter.report(.fallbackBuildStarted(filePath: file.originalPath))

        let artifact: BuildArtifact
        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            do {
                artifact = try await BuildStage(launcher: deps.launcher).build(
                    sandbox: sandbox,
                    scheme: scheme,
                    destination: destination,
                    timeout: configuration.build.timeout
                )
                await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: true))
            } catch {
                await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: false))
                try? sandbox.cleanup()
                return await markUnviable(mutants: fileMutants)
            }

        case .spm:
            do {
                artifact = try await BuildStage(launcher: deps.launcher).buildSPM(
                    sandbox: sandbox,
                    timeout: configuration.build.timeout
                )
                await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: true))
            } catch {
                await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: false))
                try? sandbox.cleanup()
                return await markUnviable(mutants: fileMutants)
            }
        }

        let context = TestExecutionContext(
            artifact: artifact, sandboxes: [sandbox], pool: pool,
            configuration: configuration
        )

        let stageResults = try await TestExecutionStage(deps: deps).execute(mutants: fileMutants, in: context)
        try? sandbox.cleanup()
        return stageResults
    }

    private func cachedResults(for mutants: [MutantDescriptor]) async -> [ExecutionResult]? {
        guard !configuration.build.noCache else { return nil }

        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant)
            guard let status = await deps.cacheStore.result(for: key) else { return nil }
            let killerTestFile = await deps.cacheStore.killerTestFile(for: key)
            results.append(
                ExecutionResult(
                    descriptor: mutant, status: status, testDuration: 0, killerTestFile: killerTestFile
                ))
        }

        for result in results {
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(
                    descriptor: result.descriptor, status: result.status,
                    index: index, total: deps.counter.total))
        }

        return results
    }

    private func markUnviable(mutants: [MutantDescriptor]) async -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant)
            await deps.cacheStore.store(status: .unviable, for: key)
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(descriptor: mutant, status: .unviable, index: index, total: deps.counter.total))
            results.append(ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0))
        }
        return results
    }
}
