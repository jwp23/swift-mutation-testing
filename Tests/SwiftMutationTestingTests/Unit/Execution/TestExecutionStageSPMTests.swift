import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestExecutionStage SPM bundle execution")
struct TestExecutionStageSPMTests {

    @Test("Given SPM artifact, when mutant executed, then its test bundle runs under xctest with the mutant selected")
    func spmMutantRunsTestBundleDirectly() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let sandbox = Sandbox(rootURL: dir)
        let context = makeSPMContext(
            sandboxes: [sandbox],
            bundlePaths: [".build/debug/MyLibTests.xctest"]
        )

        _ = try await makeStage(launcher: launcher, in: dir)
            .execute(mutants: [makeSPMMutant(id: "m0")], in: context)

        let requests = await launcher.requests
        let request = try #require(requests.first)

        #expect(requests.count == 1)
        #expect(request.executableURL.path == "/usr/bin/xcrun")
        #expect(
            request.arguments == [
                "xctest", dir.appendingPathComponent(".build/debug/MyLibTests.xctest").path,
            ]
        )
        #expect(request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] == "m0")
        #expect(request.workingDirectoryURL == dir)
    }

    @Test("Given one sandbox per worker, when mutants run concurrently, then each worker uses its own sandbox")
    func concurrentWorkersUseOwnSandboxes() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let first = Sandbox(rootURL: dir.appendingPathComponent("worker-0"))
        let second = Sandbox(rootURL: dir.appendingPathComponent("worker-1"))
        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [first, second],
            bundlePaths: [".build/debug/MyLibTests.xctest"],
            concurrency: 2
        )

        _ = try await makeStage(launcher: launcher, in: dir, total: 2)
            .execute(
                mutants: [makeSPMMutant(id: "m0"), makeSPMMutant(id: "m1")],
                in: context
            )

        let requests = await launcher.requests
        let workingDirectories = Set(requests.map(\.workingDirectoryURL))

        #expect(workingDirectories == Set([first.rootURL, second.rootURL]))
    }

    @Test("Given four workers, when four mutants execute, then their test runs are in flight at the same time")
    func workersRunMutantsInParallel() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = ConcurrencyTrackingLauncher()
        let sandboxes = (0 ..< 4).map { Sandbox(rootURL: dir.appendingPathComponent("worker-\($0)")) }
        let context = makeSPMContext(
            sandboxes: sandboxes,
            bundlePaths: [".build/debug/MyLibTests.xctest"],
            concurrency: 4
        )

        _ = try await makeStage(launcher: launcher, in: dir, total: 4)
            .execute(mutants: (0 ..< 4).map { makeSPMMutant(id: "m\($0)") }, in: context)

        #expect(await launcher.peakInFlight == 4)
    }

    @Test("Given several test bundles, when a mutant survives the first, then the remaining bundles also run")
    func survivingMutantRunsEveryBundle() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"]
        )

        let results = try await makeStage(launcher: launcher, in: dir)
            .execute(mutants: [makeSPMMutant(id: "m0")], in: context)

        let requests = await launcher.requests

        #expect(requests.count == 2)
        #expect(results.first?.status == .survived)
    }

    @Test("Given several test bundles, when the first bundle kills the mutant, then no further bundle runs")
    func killedMutantStopsAfterFailingBundle() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(
            outcomes: [(exitCode: 1, output: "Test Case '-[MySuite myTest]' failed (0.001 seconds).")]
        )
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"]
        )

        let results = try await makeStage(launcher: launcher, in: dir)
            .execute(mutants: [makeSPMMutant(id: "m0")], in: context)

        let requests = await launcher.requests

        #expect(requests.count == 1)
        #expect(results.first?.status == .killed(by: "MySuite.myTest"))
    }

    @Test("Given a configured test target, when mutant executed, then only that target's bundle runs")
    func testTargetSelectsMatchingBundle() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"],
            testTarget: "BTests"
        )

        _ = try await makeStage(launcher: launcher, in: dir)
            .execute(mutants: [makeSPMMutant(id: "m0")], in: context)

        let requests = await launcher.requests

        #expect(requests.count == 1)
        #expect(requests.first?.arguments.last?.hasSuffix("BTests.xctest") == true)
    }

    @Test("Given a test target naming a class and method, when mutant executed, then the bundle runs that selection")
    func testTargetSelectionIsPassedToTheBundle() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"],
            testTarget: "BTests/SomeSuite/testSomething"
        )

        _ = try await makeStage(launcher: launcher, in: dir)
            .execute(mutants: [makeSPMMutant(id: "m0")], in: context)

        let requests = await launcher.requests
        let request = try #require(requests.first)

        #expect(requests.count == 1)
        #expect(request.arguments.dropLast() == ["xctest", "-XCTest", "SomeSuite/testSomething"])
        #expect(request.arguments.last?.hasSuffix("BTests.xctest") == true)
    }

    @Test("Given a test target naming no built bundle, when mutants execute, then the run fails with a clear error")
    func unmatchedTestTargetFailsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"],
            testTarget: "MyPackagePackageTests"
        )

        await #expect(throws: BuildError.testTargetUnscopable(testTarget: "MyPackagePackageTests")) {
            try await makeStage(launcher: launcher, in: dir)
                .execute(mutants: [makeSPMMutant(id: "m0")], in: context)
        }

        #expect(await launcher.requests.isEmpty)
    }

    @Test("Given fewer sandboxes than workers, when mutants execute, then no two of them are in flight together")
    func workersNeverShareASandbox() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = ConcurrencyTrackingLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"],
            concurrency: 4
        )

        _ = try await makeStage(launcher: launcher, in: dir, total: 4)
            .execute(mutants: (0 ..< 4).map { makeSPMMutant(id: "m\($0)") }, in: context)

        #expect(await launcher.peakInFlight == 1)
    }

    @Test("Given a test file named for the mutant's source, when it runs, then those tests run before the suite")
    func likelyKillerTestsRunBeforeTheFullSuite() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"]
        )

        let results = try await makeStage(
            launcher: launcher, in: dir, testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)]
        )
        .execute(mutants: [makeSPMMutant(id: "m0", filePath: "/p/Sources/Foo.swift")], in: context)

        let requests = await launcher.requests
        let bundlePath = dir.appendingPathComponent(".build/debug/MyLibTests.xctest").path

        #expect(requests.count == 2)
        #expect(requests.first?.arguments == ["xctest", "-XCTest", "FooTests", bundlePath])
        #expect(requests.last?.arguments == ["xctest", bundlePath])
        #expect(results.first?.status == .survived)
    }

    @Test("Given the likely killers kill the mutant, when it runs, then the full suite never runs")
    func likelyKillerKillStopsBeforeTheFullSuite() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(
            outcomes: [(exitCode: 1, output: "Test Case '-[FooTests testAddsUp]' failed (0.001 seconds).")]
        )
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"]
        )

        let results = try await makeStage(
            launcher: launcher, in: dir, testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)]
        )
        .execute(mutants: [makeSPMMutant(id: "m0", filePath: "/p/Sources/Foo.swift")], in: context)

        #expect(await launcher.requests.count == 1)
        #expect(results.first?.status == .killed(by: "FooTests.testAddsUp"))
    }

    @Test("Given the likely killers pass, when the full suite kills the mutant, then the suite's test is named")
    func fullSuiteKillNamesItsOwnFailingTest() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(
            outcomes: [
                (exitCode: 0, output: "Test Case '-[FooTests testAddsUp]' passed (0.001 seconds)."),
                (exitCode: 1, output: "Test Case '-[WiringTests testEndToEnd]' failed (0.001 seconds)."),
            ]
        )
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"]
        )

        let results = try await makeStage(
            launcher: launcher, in: dir, testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)]
        )
        .execute(mutants: [makeSPMMutant(id: "m0", filePath: "/p/Sources/Foo.swift")], in: context)

        #expect(await launcher.requests.count == 2)
        #expect(results.first?.status == .killed(by: "WiringTests.testEndToEnd"))
    }

    @Test("Given no test file named for the mutant's source, when it runs, then only the full suite runs")
    func sourceWithoutLikelyKillersRunsOnlyTheFullSuite() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"]
        )

        _ = try await makeStage(
            launcher: launcher, in: dir, testFilePaths: [try writeXCTestFile(named: "BarTests.swift", in: dir)]
        )
        .execute(mutants: [makeSPMMutant(id: "m0", filePath: "/p/Sources/Foo.swift")], in: context)

        let requests = await launcher.requests

        #expect(requests.count == 1)
        #expect(requests.first?.arguments.contains("-XCTest") == false)
    }

    @Test("Given the source's test file uses Swift Testing, when its mutant runs, then only the full suite runs")
    func swiftTestingTestFileSkipsTheLikelyKillerRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"]
        )

        _ = try await makeStage(
            launcher: launcher, in: dir,
            testFilePaths: [try writeSwiftTestingFile(named: "FooTests.swift", in: dir)]
        )
        .execute(mutants: [makeSPMMutant(id: "m0", filePath: "/p/Sources/Foo.swift")], in: context)

        let requests = await launcher.requests

        #expect(requests.count == 1)
        #expect(requests.first?.arguments.contains("-XCTest") == false)
    }

    @Test("Given a test target naming a class, when a mutant runs, then that selection runs instead of likely killers")
    func configuredSelectionTakesPrecedenceOverLikelyKillers() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()
        let context = makeSPMContext(
            sandboxes: [Sandbox(rootURL: dir)],
            bundlePaths: [".build/debug/MyLibTests.xctest"],
            testTarget: "MyLibTests/SomeSuite"
        )

        _ = try await makeStage(
            launcher: launcher, in: dir, testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)]
        )
        .execute(mutants: [makeSPMMutant(id: "m0", filePath: "/p/Sources/Foo.swift")], in: context)

        let requests = await launcher.requests

        #expect(requests.count == 1)
        #expect(requests.first?.arguments.dropLast() == ["xctest", "-XCTest", "SomeSuite"])
    }

    @Test("Given an SPM artifact without test bundles, when mutant executed, then the error is propagated")
    func missingTestBundleFailsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let context = makeSPMContext(sandboxes: [Sandbox(rootURL: dir)], bundlePaths: [])

        await #expect(throws: BuildError.testBundleNotFound) {
            try await makeStage(launcher: RecordingProcessLauncher(), in: dir)
                .execute(mutants: [makeSPMMutant(id: "m0")], in: context)
        }
    }
}

private func makeStage(
    launcher: any ProcessLaunching,
    in dir: URL,
    total: Int = 1,
    reporter: MockProgressReporter = MockProgressReporter(),
    testFilePaths: [String] = []
) -> TestExecutionStage {
    TestExecutionStage(
        deps: makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path,
            reporter: reporter,
            total: total,
            testFilePaths: testFilePaths
        )
    )
}

private func makeSPMContext(
    sandboxes: [Sandbox],
    bundlePaths: [String],
    concurrency: Int = 1,
    testTarget: String? = nil
) -> TestExecutionContext {
    TestExecutionContext(
        artifact: BuildArtifact(
            derivedDataPath: sandboxes[0].rootURL.appendingPathComponent(".build").path,
            xctestrunURL: nil,
            plist: nil,
            testBundlePaths: bundlePaths
        ),
        sandboxes: sandboxes,
        pool: makeSimulatorPool(),
        configuration: makeRunnerConfiguration(
            projectType: .spm,
            testTarget: testTarget,
            concurrency: concurrency,
            noCache: true
        )
    )
}

private func writeXCTestFile(named fileName: String, in directory: URL) throws -> String {
    let className = (fileName as NSString).deletingPathExtension
    try FileHelpers.write(
        "import XCTest\n\nfinal class \(className): XCTestCase {}\n",
        named: fileName,
        in: directory
    )
    return directory.appendingPathComponent(fileName).path
}

private func writeSwiftTestingFile(named fileName: String, in directory: URL) throws -> String {
    let suiteName = (fileName as NSString).deletingPathExtension
    try FileHelpers.write(
        "import Testing\n\nstruct \(suiteName) {\n    @Test func something() {}\n}\n",
        named: fileName,
        in: directory
    )
    return directory.appendingPathComponent(fileName).path
}

private func makeSPMMutant(id: String, filePath: String = "/tmp/Foo.swift") -> MutantDescriptor {
    makeMutantDescriptor(
        id: id,
        filePath: filePath,
        originalText: "a + b",
        mutatedText: "a - b",
        operatorIdentifier: "binaryOperator",
        description: "Replace + with -",
        isSchematizable: true
    )
}
