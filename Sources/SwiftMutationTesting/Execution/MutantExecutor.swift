import Foundation

struct MutantExecutor: Sendable {

    init(configuration: RunnerConfiguration, launcher: any ProcessLaunching) {
        self.configuration = configuration
        self.launcher = launcher
    }

    private let configuration: RunnerConfiguration
    private let launcher: any ProcessLaunching

    private struct MutantRunContext {
        let deps: ExecutionDeps
        let input: RunnerInput
        let sandboxes: [Sandbox]
        let pool: SimulatorPool
        let artifact: BuildArtifact?
        let schemaBuildExcluded: [MutantDescriptor]
    }

    private struct RetryContext {
        let sandbox: Sandbox
        let input: RunnerInput
        let stage: BuildStage
        let deps: ExecutionDeps
        let start: Date
    }

    private struct ExecutionSetup {
        let artifact: BuildArtifact?
        let schemaBuildExcluded: [MutantDescriptor]
        let sandboxes: [Sandbox]
        let pool: SimulatorPool
    }

    func execute(_ input: RunnerInput) async throws -> [ExecutionResult] {
        let reporter: any ProgressReporter =
            configuration.reporting.quiet
            ? SilentProgressReporter()
            : ConsoleProgressReporter()

        let (cacheStore, metadata, hasher) = try await prepareCacheStore(input: input)

        if let cached = await allCached(mutants: input.mutants, cacheStore: cacheStore) {
            await reporter.report(.loadedFromCache(mutantCount: cached.count))
            try await cacheStore.persist()
            try await cacheStore.persistMetadata(metadata)
            return cached
        }

        let deps = makeExecutionDeps(
            input: input, hasher: hasher, cacheStore: cacheStore, reporter: reporter
        )

        let setup = try await prepareExecution(input: input, deps: deps)
        await reporter.report(.simulatorPoolReady(size: setup.pool.size))

        let results: [ExecutionResult]
        do {
            results = try await runAllMutants(
                MutantRunContext(
                    deps: deps,
                    input: input,
                    sandboxes: setup.sandboxes,
                    pool: setup.pool,
                    artifact: setup.artifact,
                    schemaBuildExcluded: setup.schemaBuildExcluded
                )
            )
        } catch {
            await setup.pool.tearDown()
            cleanUp(setup.sandboxes)
            throw error
        }

        await setup.pool.tearDown()
        cleanUp(setup.sandboxes)
        try await cacheStore.persist()
        try await cacheStore.persistMetadata(metadata)

        return results
    }

    /// Builds the artifact, replicates worker sandboxes and stands up the simulator pool. Any
    /// failure along the way leaves nothing behind: every sandbox registered so far — the build
    /// sandbox and any worker replicas already created — is removed before the error propagates.
    private func prepareExecution(input: RunnerInput, deps: ExecutionDeps) async throws -> ExecutionSetup {
        let sandbox = try await SandboxFactory().create(
            projectPath: input.projectPath,
            schematizedFiles: input.schematizedFiles,
            supportFileContent: input.supportFileContent
        )
        SandboxCleaner.register(sandbox)

        do {
            let (artifact, schemaBuildExcluded) = try await buildArtifact(sandbox: sandbox, input: input, deps: deps)
            let sandboxes = try workerSandboxes(
                buildSandbox: sandbox,
                artifact: artifact,
                mutantCount: testableSchematizableMutants(in: input, excluding: schemaBuildExcluded).count
            )
            let pool = try await makePool(launcher: launcher)
            try await pool.setUp()

            return ExecutionSetup(
                artifact: artifact,
                schemaBuildExcluded: schemaBuildExcluded,
                sandboxes: sandboxes,
                pool: pool
            )
        } catch {
            SandboxCleaner.cleanupActiveSandboxes()
            throw error
        }
    }

    /// The sandboxes this run's workers execute in: the sandbox that was built, plus a copy of it
    /// for every other worker. SPM workers run the built test bundles concurrently, and a copy
    /// each keeps them out of one another's build directory. Xcode workers select their tests
    /// through an xctestrun plist against one shared build, so they need no copies.
    ///
    /// A run never makes more sandboxes than it has mutants to put in them. Copying a build
    /// directory is not cheap, and a scoped run of a handful of mutants on a many-core machine
    /// would otherwise pay for a copy per core, most of them for workers with nothing to run.
    private func workerSandboxes(
        buildSandbox: Sandbox,
        artifact: BuildArtifact?,
        mutantCount: Int
    ) throws -> [Sandbox] {
        guard artifact != nil, case .spm = configuration.build.projectType else { return [buildSandbox] }

        let factory = SandboxFactory()
        var sandboxes = [buildSandbox]
        let workers = max(1, min(configuration.build.concurrency, mutantCount))

        for _ in 1 ..< workers {
            let replica = try factory.replicate(buildSandbox)
            SandboxCleaner.register(replica)
            sandboxes.append(replica)
        }

        return sandboxes
    }

    /// The mutants that run their tests against the schema build: every schematizable mutant the
    /// build did not have to exclude to compile. The excluded ones are re-routed to a per-file
    /// build of their own and never occupy a worker sandbox.
    private func testableSchematizableMutants(
        in input: RunnerInput,
        excluding schemaBuildExcluded: [MutantDescriptor]
    ) -> [MutantDescriptor] {
        let excludedIDs = Set(schemaBuildExcluded.map(\.id))

        return input.mutants.filter { $0.isSchematizable && !excludedIDs.contains($0.id) }
    }

    private func cleanUp(_ sandboxes: [Sandbox]) {
        for sandbox in sandboxes {
            try? sandbox.cleanup()
        }
        SandboxCleaner.deregister()
    }

    private func prepareCacheStore(
        input: RunnerInput
    ) async throws -> (CacheStore, CacheStore.CacheMetadata, TestFilesHasher) {
        let cachePath = URL(fileURLWithPath: configuration.projectPath)
            .appendingPathComponent("\(CacheStore.directoryName)/results.json").path
        let cacheStore = CacheStore(
            storePath: cachePath, projectPath: configuration.projectPath, noCache: configuration.build.noCache
        )
        try await cacheStore.load()

        let hasher = TestFilesHasher()
        let currentTestHashes = hasher.hashPerFile(projectPath: input.projectPath)
        let diff = try await cacheStore.changedTestFiles(current: currentTestHashes)
        await cacheStore.invalidate(diff: diff)

        let metadata = CacheStore.CacheMetadata(testFileHashes: currentTestHashes)
        return (cacheStore, metadata, hasher)
    }

    private func makeExecutionDeps(
        input: RunnerInput,
        hasher: TestFilesHasher,
        cacheStore: CacheStore,
        reporter: any ProgressReporter
    ) -> ExecutionDeps {
        let mutantCount = input.mutants.count
        let counter = MutationCounter(total: mutantCount)
        let testFilePaths = hasher.testFilePaths(projectPath: input.projectPath)
        let resolver = KillerTestFileResolver(testFilePaths: testFilePaths)
        let likelyKillers = LikelyKillerTestSelector(
            testFilePaths: testFilePaths,
            overrides: configuration.build.likelyKillerTests
        )
        return ExecutionDeps(
            launcher: launcher, cacheStore: cacheStore, reporter: reporter,
            counter: counter, killerTestFileResolver: resolver,
            likelyKillerTestSelector: likelyKillers
        )
    }

    private func runAllMutants(
        _ context: MutantRunContext
    ) async throws -> [ExecutionResult] {
        let deps = context.deps
        let input = context.input
        let sandboxes = context.sandboxes
        let pool = context.pool
        let artifact = context.artifact
        let schemaBuildExcluded = context.schemaBuildExcluded
        let incompatible = input.mutants.filter { !$0.isSchematizable }

        var results: [ExecutionResult] = []

        var reroutedToIncompatible: [MutantDescriptor] = []
        var sourceCache: [String: String] = [:]
        let rewriter = MutationRewriter()

        for mutant in schemaBuildExcluded {
            if let rerouted = rewriteForIncompatible(mutant, rewriter: rewriter, sourceCache: &sourceCache) {
                reroutedToIncompatible.append(rerouted)
            } else {
                let key = MutantCacheKey.make(for: mutant)
                await deps.cacheStore.store(status: .unviable, for: key)
                let index = await deps.counter.increment()
                await deps.reporter.report(
                    .mutantFinished(descriptor: mutant, status: .unviable, index: index, total: deps.counter.total))
                results.append(ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0))
            }
        }

        let testableSchematizable = testableSchematizableMutants(in: input, excluding: schemaBuildExcluded)

        if let artifact {
            var baseline: BaselineMeasurement?
            if case .spm = configuration.build.projectType {
                baseline = try await measureSPMBaseline(
                    artifact: artifact, sandbox: sandboxes[0], deps: deps
                )
            }
            let context = TestExecutionContext(
                artifact: artifact, sandboxes: sandboxes, pool: pool,
                configuration: configuration, baseline: baseline
            )
            results += try await runNormal(deps: deps, context: context, schematizable: testableSchematizable)
        } else if !testableSchematizable.isEmpty {
            results += try await runFallback(
                deps: deps, input: input, mutants: testableSchematizable, pool: pool
            )
        }

        results += try await runIncompatible(
            deps: deps, mutants: incompatible + reroutedToIncompatible, pool: pool
        )

        return results
    }

    private func allCached(
        mutants: [MutantDescriptor],
        cacheStore: CacheStore
    ) async -> [ExecutionResult]? {
        guard !configuration.build.noCache, !mutants.isEmpty else { return nil }

        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant)
            guard let status = await cacheStore.result(for: key) else { return nil }
            let killerTestFile = await cacheStore.killerTestFile(for: key)
            results.append(
                ExecutionResult(
                    descriptor: mutant, status: status, testDuration: 0, killerTestFile: killerTestFile
                ))
        }

        return results
    }

    private func buildArtifact(
        sandbox: Sandbox,
        input: RunnerInput,
        deps: ExecutionDeps
    ) async throws -> (BuildArtifact?, [MutantDescriptor]) {
        await deps.reporter.report(.buildStarted)
        let start = Date()
        let stage = BuildStage(launcher: deps.launcher)

        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            do {
                let artifact = try await stage.build(
                    sandbox: sandbox,
                    scheme: scheme,
                    destination: destination,
                    timeout: configuration.build.buildTimeout
                )
                await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
                return (artifact, [])
            } catch BuildError.compilationFailed(_) {
                return (nil, [])
            }

        case .spm:
            do {
                let artifact = try await stage.buildSPM(
                    sandbox: sandbox,
                    timeout: configuration.build.buildTimeout
                )
                await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
                return (artifact, [])
            } catch BuildError.compilationFailed(let output) {
                let retryCtx = RetryContext(
                    sandbox: sandbox, input: input,
                    stage: stage, deps: deps, start: start
                )
                let (artifact, excluded) = try await retryExcludingErrors(
                    output: output,
                    context: retryCtx,
                    alreadyExcluded: []
                )
                return (artifact, excluded)
            }
        }
    }

    private func retryExcludingErrors(
        output: String,
        context: RetryContext,
        alreadyExcluded: [MutantDescriptor]
    ) async throws -> (BuildArtifact?, [MutantDescriptor]) {
        let sandbox = context.sandbox
        let input = context.input
        let sandboxRoot = canonicalPath(sandbox.rootURL.path)
        let projectRoot = URL(fileURLWithPath: input.projectPath).resolvingSymlinksInPath().path
        let errorSandboxPaths = UncompilableMutants.erroringSourcePaths(in: output, sandboxRoot: sandboxRoot)
        let alreadyExcludedIDs = Set(alreadyExcluded.map(\.id))

        var newlyExcluded: [MutantDescriptor] = []

        for sandboxPath in errorSandboxPaths {
            let relative = String(sandboxPath.dropFirst(sandboxRoot.count))
            let originalPath = projectRoot + relative

            guard FileManager.default.fileExists(atPath: originalPath) else { continue }

            let mutantsInFile = input.mutants.filter { mutant in
                mutant.isSchematizable
                    && !alreadyExcludedIDs.contains(mutant.id)
                    && URL(fileURLWithPath: mutant.filePath).resolvingSymlinksInPath().path == originalPath
            }

            guard !mutantsInFile.isEmpty else { continue }

            newlyExcluded += UncompilableMutants.removeFromSandbox(
                sandboxPath: sandboxPath,
                originalPath: originalPath,
                errorOutput: output,
                mutantsInFile: mutantsInFile
            )
        }

        guard !newlyExcluded.isEmpty else {
            return (nil, alreadyExcluded)
        }

        let allExcluded = alreadyExcluded + newlyExcluded

        do {
            let artifact = try await context.stage.buildSPM(
                sandbox: sandbox,
                timeout: configuration.build.buildTimeout
            )
            await context.deps.reporter.report(
                .buildFinished(duration: Date().timeIntervalSince(context.start))
            )
            return (artifact, allExcluded)
        } catch BuildError.compilationFailed(let newOutput) {
            return try await retryExcludingErrors(
                output: newOutput,
                context: context,
                alreadyExcluded: allExcluded
            )
        }
    }

    private func runNormal(
        deps: ExecutionDeps,
        context: TestExecutionContext,
        schematizable: [MutantDescriptor]
    ) async throws -> [ExecutionResult] {
        try await TestExecutionStage(deps: deps).execute(mutants: schematizable, in: context)
    }

    private func runFallback(
        deps: ExecutionDeps,
        input: RunnerInput,
        mutants: [MutantDescriptor],
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        try await FallbackExecutor(deps: deps, configuration: configuration)
            .execute(input: input, mutants: mutants, pool: pool)
    }

    private func runIncompatible(
        deps: ExecutionDeps,
        mutants: [MutantDescriptor],
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        try await IncompatibleMutantExecutor(deps: deps, sandboxFactory: SandboxFactory())
            .execute(mutants, configuration: configuration, pool: pool)
    }

    /// Runs the unmutated suite once, before any mutant does, in the sandbox that was built. A
    /// suite that already fails makes every mutant look killed, so a failing baseline ends the run
    /// here; a passing one leaves behind the timings each mutant's timeout is measured against.
    ///
    /// Its own timeout is the longest any mutant could be given from the configured one, since how
    /// long the suite takes is the very thing this run exists to find out: bounding the
    /// measurement by the per-mutant floor would end the run on any suite slower than that floor,
    /// which is the case the measurement is for.
    private func measureSPMBaseline(
        artifact: BuildArtifact,
        sandbox: Sandbox,
        deps: ExecutionDeps
    ) async throws -> BaselineMeasurement {
        try await BaselineRunner(launcher: deps.launcher).measure(
            selection: BundleSelection.resolve(
                artifact: artifact,
                testTarget: configuration.build.testTarget,
                testingFramework: configuration.build.testingFramework
            ),
            sandbox: sandbox,
            timeout: configuration.build.timeout * MutantTimeout.baselineCoefficient
        )
    }

    private func rewriteForIncompatible(
        _ mutant: MutantDescriptor,
        rewriter: MutationRewriter,
        sourceCache: inout [String: String]
    ) -> MutantDescriptor? {
        let source: String
        if let cached = sourceCache[mutant.filePath] {
            source = cached
        } else {
            guard let loaded = try? String(contentsOfFile: mutant.filePath, encoding: .utf8) else {
                return nil
            }
            sourceCache[mutant.filePath] = loaded
            source = loaded
        }

        let point = MutationPoint(
            operatorIdentifier: mutant.operatorIdentifier,
            filePath: mutant.filePath,
            line: mutant.line,
            column: mutant.column,
            utf8Offset: mutant.utf8Offset,
            originalText: mutant.originalText,
            mutatedText: mutant.mutatedText,
            replacement: mutant.replacementKind,
            description: mutant.description
        )

        let content = rewriter.rewrite(source: source, applying: point)
        guard content != source else { return nil }

        return MutantDescriptor(
            id: mutant.id,
            filePath: mutant.filePath,
            line: mutant.line,
            column: mutant.column,
            utf8Offset: mutant.utf8Offset,
            originalText: mutant.originalText,
            mutatedText: mutant.mutatedText,
            operatorIdentifier: mutant.operatorIdentifier,
            replacementKind: mutant.replacementKind,
            description: mutant.description,
            isSchematizable: mutant.isSchematizable,
            mutatedSourceContent: content
        )
    }

    private func canonicalPath(_ path: String) -> String {
        path.withCString { ptr in
            guard let resolved = realpath(ptr, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    private func makePool(launcher: any ProcessLaunching) async throws -> SimulatorPool {
        let destination: String
        if case .xcode(_, let dest) = configuration.build.projectType {
            destination = dest
        } else {
            destination = "platform=macOS"
        }

        guard SimulatorManager.requiresSimulatorPool(for: destination) else {
            return SimulatorPool(
                baseUDID: nil, size: configuration.build.concurrency,
                destination: destination, launcher: launcher
            )
        }

        let baseUDID = try await SimulatorManager(launcher: launcher)
            .resolveBaseUDID(for: destination)

        return SimulatorPool(
            baseUDID: baseUDID, size: configuration.build.concurrency,
            destination: destination, launcher: launcher
        )
    }
}
