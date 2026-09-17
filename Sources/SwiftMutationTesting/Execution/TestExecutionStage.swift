import Foundation

struct TestExecutionStage: Sendable {
    let deps: ExecutionDeps

    /// Bundles a mutant's tests run in, and the XCTest selection applied inside them. A configured
    /// test target names the bundle with its first path component; anything after that is an
    /// XCTest selector (`Class` or `Class/method`). A target naming no bundle — what a toolchain
    /// that merges every test target into one bundle produces — falls back to every bundle, with
    /// any selector still applied, and is reported so the fallback is never silent.
    private struct BundleSelection {
        let paths: [String]
        let xctestSelection: String?
        let matchedTestTarget: Bool
    }

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        let concurrency = effectiveConcurrency(in: context)

        await reportUnmatchedTestTarget(in: context)

        try await withThrowingTaskGroup(of: (worker: Int, result: ExecutionResult).self) { group in
            var workers = 0
            var iterator = mutants.makeIterator()

            while workers < concurrency, let mutant = iterator.next() {
                let key = MutantCacheKey.make(for: mutant)
                let worker = workers
                group.addTask { (worker, try await self.run(mutant: mutant, key: key, worker: worker, in: context)) }
                workers += 1
            }

            for try await finished in group {
                results.append(finished.result)
                if let next = iterator.next() {
                    let key = MutantCacheKey.make(for: next)
                    let worker = finished.worker
                    group.addTask { (worker, try await self.run(mutant: next, key: key, worker: worker, in: context)) }
                }
            }
        }

        return results
    }

    /// Workers must never share a sandbox: `sandbox(forWorker:)` wraps, so running more workers
    /// than there are sandboxes would put two live mutants in one working directory and one build
    /// directory. SPM mutants therefore run at most one worker per sandbox — which also keeps the
    /// per-file fallback path, with its single sandbox, serialized. Xcode mutants share the one
    /// build sandbox by design, selecting their tests through a per-mutant xctestrun file.
    private func effectiveConcurrency(in context: TestExecutionContext) -> Int {
        let configured = context.configuration.build.concurrency

        guard context.artifact.plist == nil else { return configured }

        return max(1, min(configured, context.sandboxes.count))
    }

    private func reportUnmatchedTestTarget(in context: TestExecutionContext) async {
        guard
            context.artifact.plist == nil,
            let testTarget = context.configuration.build.testTarget,
            !bundleSelection(in: context).matchedTestTarget
        else { return }

        await deps.reporter.report(.testTargetMatchedNoBundle(testTarget: testTarget))
    }

    private func run(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        worker: Int,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        if !context.configuration.build.noCache, let cached = await deps.cacheStore.result(for: key) {
            let killerTestFile = await deps.cacheStore.killerTestFile(for: key)
            let result = ExecutionResult(
                descriptor: mutant, status: cached, testDuration: 0, killerTestFile: killerTestFile
            )
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(descriptor: mutant, status: cached, index: index, total: deps.counter.total))
            return result
        }

        guard let plist = context.artifact.plist else {
            return try await runSPM(mutant: mutant, key: key, worker: worker, in: context)
        }

        let plistData = plist.activating(mutant.id)
        let slot = try await context.pool.acquire()
        let launched: TestLaunchResult
        do {
            launched = try await launch(plistData: plistData, slot: slot, worker: worker, in: context)
        } catch {
            await context.pool.release(slot)
            throw error
        }

        await context.pool.release(slot)

        let outcome = try await ResultParser(launcher: deps.launcher).parse(
            exitCode: launched.exitCode,
            output: launched.output,
            xcresultPath: launched.xcresultPath,
            timeout: context.configuration.build.timeout
        )
        try? FileManager.default.removeItem(atPath: launched.xcresultPath)

        return await recordResult(mutant: mutant, key: key, outcome: outcome, duration: launched.duration)
    }

    /// SPM mutants run the prebuilt test bundles straight from the worker's own sandbox, so they
    /// need no simulator slot — the pool exists for destinations that boot a simulator.
    private func runSPM(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        worker: Int,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        let launched = try await launchSPM(mutant: mutant, worker: worker, in: context)
        let outcome = SPMResultParser().parse(exitCode: launched.exitCode, output: launched.output)
        return await recordResult(mutant: mutant, key: key, outcome: outcome, duration: launched.duration)
    }

    private func recordResult(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        outcome: TestRunOutcome,
        duration: Double
    ) async -> ExecutionResult {
        let status = outcome.asExecutionStatus
        let killerTestFile = resolveKillerTestFile(status: status)
        let result = ExecutionResult(
            descriptor: mutant, status: status, testDuration: duration,
            killerTestFile: killerTestFile
        )
        await deps.cacheStore.store(status: status, for: key, killerTestFile: killerTestFile)
        let index = await deps.counter.increment()
        await deps.reporter.report(
            .mutantFinished(
                descriptor: mutant, status: status,
                index: index, total: deps.counter.total
            )
        )
        return result
    }

    private func resolveKillerTestFile(status: ExecutionStatus) -> String? {
        guard case .killed(let testName) = status else { return nil }
        return deps.killerTestFileResolver.resolve(testName: testName)
    }

    /// Runs the mutant's test bundles in the worker's sandbox, selecting the mutant through the
    /// environment. Bundles run in turn until one reports a failure — a mutant a bundle already
    /// killed cannot be killed harder by the next one — and each run only gets what is left of
    /// the mutant's timeout.
    private func launchSPM(
        mutant: MutantDescriptor,
        worker: Int,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        let selection = bundleSelection(in: context)
        let bundlePaths = selection.paths

        guard !bundlePaths.isEmpty else { throw BuildError.testBundleNotFound }

        let sandbox = context.sandbox(forWorker: worker)
        let timeout = context.configuration.build.timeout
        let start = Date()
        var output = ""
        var exitCode: Int32 = 0

        for bundlePath in bundlePaths {
            let remaining = timeout - Date().timeIntervalSince(start)

            guard remaining > 0 else {
                return TestLaunchResult(
                    exitCode: SPMResultParser.timeoutExitCode,
                    output: output,
                    xcresultPath: "",
                    duration: Date().timeIntervalSince(start)
                )
            }

            var arguments = ["xctest"]

            if let xctestSelection = selection.xctestSelection {
                arguments += ["-XCTest", xctestSelection]
            }

            arguments.append(sandbox.rootURL.appendingPathComponent(bundlePath).path)

            let captured = try await deps.launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                    arguments: arguments,
                    environment: nil,
                    additionalEnvironment: [
                        "__SWIFT_MUTATION_TESTING_ACTIVE": mutant.id
                    ],
                    workingDirectoryURL: sandbox.rootURL,
                    timeout: remaining
                )
            )

            output += captured.output
            exitCode = captured.exitCode

            if exitCode != 0 { break }
        }

        return TestLaunchResult(
            exitCode: exitCode,
            output: output,
            xcresultPath: "",
            duration: Date().timeIntervalSince(start)
        )
    }

    private func bundleSelection(in context: TestExecutionContext) -> BundleSelection {
        let allPaths = context.artifact.testBundlePaths

        guard let testTarget = context.configuration.build.testTarget else {
            return BundleSelection(paths: allPaths, xctestSelection: nil, matchedTestTarget: true)
        }

        var components = testTarget.components(separatedBy: "/")
        let targetName = components.removeFirst()
        let matching = allPaths.filter {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent == targetName
        }

        return BundleSelection(
            paths: matching.isEmpty ? allPaths : matching,
            xctestSelection: components.isEmpty ? nil : components.joined(separator: "/"),
            matchedTestTarget: !matching.isEmpty
        )
    }

    private func launch(
        plistData: Data,
        slot: SimulatorSlot,
        worker: Int,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        let sandbox = context.sandbox(forWorker: worker)
        let baseURL =
            context.artifact.xctestrunURL?.deletingLastPathComponent()
            ?? sandbox.rootURL
        let xctestrunURL = baseURL.appendingPathComponent("\(UUID().uuidString).xctestrun")
        let xcresultPath = sandbox.rootURL
            .appendingPathComponent("\(UUID().uuidString).xcresult").path

        defer { try? FileManager.default.removeItem(at: xctestrunURL) }

        try plistData.write(to: xctestrunURL)

        var arguments = [
            "test-without-building",
            "-xctestrun", xctestrunURL.path,
            "-destination", slot.destination,
            "-resultBundlePath", xcresultPath,
            "-derivedDataPath", context.artifact.derivedDataPath,
        ]

        if let testTarget = context.configuration.build.testTarget {
            arguments += ["-only-testing", testTarget]
        }

        let start = Date()
        let captured = try await deps.launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: context.configuration.build.timeout
            )
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }
}
