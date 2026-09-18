import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor")
struct IncompatibleMutantExecutorTests {
    @Test("Given 3 mutants with content, when execute called, then 3 results are returned in order")
    func executeReturnsAllResultsInOrder() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeIncompatibleMutantExecutor(in: dir, exitCode: 1)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutants = (0 ..< 3).map {
            makeMutantDescriptor(
                id: "m\($0)",
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = \($0)"
            )
        }

        let results = try await executor.execute(
            mutants,
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.count == 3)
        #expect(results.map(\.descriptor.id) == ["m0", "m1", "m2"])
    }

    @Test("Given mutant without content, when execute called, then returns unviable without building")
    func nilContentReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeIncompatibleMutantExecutor(in: dir, exitCode: 0)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: nil
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given build failure, when execute called, then returns unviable")
    func buildFailureReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeIncompatibleMutantExecutor(in: dir, exitCode: 1)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given noCache is true, when mutant already cached, then cache is bypassed")
    func noCacheConfigurationBypassesCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let firstExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: []),
                likelyKillerTestSelector: LikelyKillerTestSelector(testFilePaths: [], overrides: [:])
            ),
            sandboxFactory: SandboxFactory()
        )
        _ = try await firstExecutor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        let noCacheConfig = makeRunnerConfiguration(projectPath: dir.path, noCache: true)
        let secondExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: []),
                likelyKillerTestSelector: LikelyKillerTestSelector(testFilePaths: [], overrides: [:])
            ),
            sandboxFactory: SandboxFactory()
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: noCacheConfig,
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given configuration with testTarget, when execute called, then testTarget is applied")
    func configurationWithTestTargetExecutesSuccessfully() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let pool = makeSimulatorPool()
        try await pool.setUp()
        let config = makeRunnerConfiguration(projectPath: dir.path, testTarget: "AppTests")
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            ),
            sandboxFactory: SandboxFactory()
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: config,
            pool: pool
        )
        #expect(results.count == 1)
    }

    @Test("Given mutant already in cache, when execute called again with invalid path, then returns cached result")
    func cachedMutantReturnsCachedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let firstExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: []),
                likelyKillerTestSelector: LikelyKillerTestSelector(testFilePaths: [], overrides: [:])
            ),
            sandboxFactory: SandboxFactory()
        )
        _ = try await firstExecutor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        let secondExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: []),
                likelyKillerTestSelector: LikelyKillerTestSelector(testFilePaths: [], overrides: [:])
            ),
            sandboxFactory: SandboxFactory()
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: "/non/existent/path"),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given launcher throws during test run, when execute called, then error is propagated")
    func launchThrowsPropagatesError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 0, throwsOnCapture: true),
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            ),
            sandboxFactory: SandboxFactory()
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        await #expect(throws: (any Error).self) {
            try await executor.execute(
                [mutant],
                configuration: makeRunnerConfiguration(projectPath: dir.path),
                pool: pool
            )
        }
    }

    @Test("Given SPM project type and exit code 0, when execute called, then mutant survived")
    func spmExitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .survived)
    }

    @Test("Given SPM project type and exit code 1 with failure output, when execute called, then mutant is killed")
    func spmExitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir, launcher: SPMBuildSuccessTestFailureMock(failureOutput: output))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .killed(by: "myTest"))
    }

    @Test("Given SPM project type and initial build failure, when execute called, then all viable mutants are unviable")
    func spmInitialBuildFailureMarksAllUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 1))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutants = [
            makeMutantDescriptor(
                id: "m0",
                filePath: sourceFile.path,
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = false"
            ),
            makeMutantDescriptor(
                id: "m1",
                filePath: sourceFile.path,
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = 0"
            ),
        ]

        let results = try await executor.execute(
            mutants,
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .unviable })
    }

    @Test("Given SPM project type with testTarget, when execute called, then filter is applied")
    func spmTestTargetFilterIsApplied() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir, launcher: SPMBuildSuccessTestFailureMock(failureOutput: output))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let config = makeRunnerConfiguration(
            projectPath: dir.path,
            projectType: .spm,
            testTarget: "FooTests"
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: config,
            pool: pool
        )

        #expect(results.count == 1)
    }

    @Test("Given SPM project type and per-mutant build failure, when execute called, then mutant is unviable")
    func spmPerMutantBuildFailureReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir, launcher: SPMInitialBuildSuccessThenFailMock())
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = INVALID"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test(
        "Given no testTarget and a likely-killer selection, when execute called, then filter uses the pipe-joined selection"
    )
    func spmNoTestTargetUsesLikelyKillerFilter() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher()
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir,
            launcher: launcher,
            likelyKillerTests: [sourceFile.path: ["FooTests.swift", "BarTests.swift"]]
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        _ = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        let requests = await launcher.requests
        #expect(requests.last?.arguments == ["test", "--skip-build", "--filter", "\\.(?:FooTests|BarTests)/"])
    }

    @Test(
        "Given a likely-killer class name with regex-special characters, when execute called, then the filter escapes each name"
    )
    func spmLikelyKillerFilterEscapesRegexSpecialCharacters() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo+Extensions.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher()
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir,
            launcher: launcher,
            likelyKillerTests: [sourceFile.path: ["Foo+ExtensionsTests.swift", "Bar.Tests.swift"]]
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        _ = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        let requests = await launcher.requests
        let escapedSelection = [
            NSRegularExpression.escapedPattern(for: "Foo+ExtensionsTests"),
            NSRegularExpression.escapedPattern(for: "Bar.Tests"),
        ].joined(separator: "|")
        let expectedFilter = "\\.(?:\(escapedSelection))/"

        #expect(requests.last?.arguments == ["test", "--skip-build", "--filter", expectedFilter])

        // The escaped filter must still match its own literal class name's specifier, unescaped would not.
        let regex = try NSRegularExpression(pattern: expectedFilter)
        let specifier = "MyPackageTests.Foo+ExtensionsTests/testSomething"
        let range = NSRange(location: 0, length: (specifier as NSString).length)
        #expect(regex.firstMatch(in: specifier, range: range) != nil)
    }

    @Test(
        "Given a likely-killer class name, when execute called, then the filter does not match an unrelated specifier that merely contains it"
    )
    func spmLikelyKillerFilterDoesNotMatchSubstringCollisions() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher()
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir,
            launcher: launcher,
            likelyKillerTests: [sourceFile.path: ["FooTests.swift"]]
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        _ = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        let requests = await launcher.requests
        let filter = try #require(requests.last?.arguments.last)
        let regex = try NSRegularExpression(pattern: filter)

        func matches(_ specifier: String) -> Bool {
            let range = NSRange(location: 0, length: (specifier as NSString).length)
            return regex.firstMatch(in: specifier, range: range) != nil
        }

        // A specifier naming exactly the likely-killer class must match.
        #expect(matches("MyPackageTests.FooTests/testSomething"))
        // Specifiers whose class name merely contains "FooTests" as a substring must not.
        #expect(!matches("MyPackageTests.MyFooTestsHelper/testSomething"))
        #expect(!matches("MyPackageTests.MyFooTests/testSomething"))
    }

    @Test("Given no testTarget and no likely-killer selection, when execute called, then no filter is added")
    func spmNoTestTargetAndNoLikelyKillerSelectionRunsWholeSuite() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher()
        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: launcher)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        _ = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        let requests = await launcher.requests
        #expect(requests.last?.arguments == ["test", "--skip-build"])
    }

    @Test(
        "Given a configured testTarget and a likely-killer selection, when execute called, then the testTarget filter wins"
    )
    func spmTestTargetTakesPrecedenceOverLikelyKillerSelection() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher()
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir,
            launcher: launcher,
            likelyKillerTests: [sourceFile.path: ["FooTests.swift"]]
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1"
        )

        _ = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, testTarget: "AppTests"),
            pool: pool
        )

        let requests = await launcher.requests
        #expect(requests.last?.arguments == ["test", "--skip-build", "--filter", "AppTests"])
    }
}
