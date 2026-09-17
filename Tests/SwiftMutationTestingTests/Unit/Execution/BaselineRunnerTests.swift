import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BaselineRunner")
struct BaselineRunnerTests {

    @Test("Given a passing suite, when the baseline is measured, then every bundle runs unmutated under xctest")
    func baselineRunsEveryBundleWithNoMutantSelected() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(
            outcomes: [
                (exitCode: 0, output: "Test Case '-[MyLibTests.FooTests testOne]' passed (0.500 seconds)."),
                (exitCode: 0, output: "Test Case '-[MyLibTests.FooTests testTwo]' passed (0.250 seconds)."),
            ]
        )

        let measurement = try await BaselineRunner(launcher: launcher).measure(
            selection: BundleSelection(
                paths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"], xctestSelection: nil
            ),
            sandbox: Sandbox(rootURL: dir),
            timeout: 60
        )

        let requests = await launcher.requests
        let request = try #require(requests.first)

        #expect(requests.count == 2)
        #expect(request.executableURL.path == "/usr/bin/xcrun")
        #expect(request.arguments == ["xctest", dir.appendingPathComponent(".build/debug/ATests.xctest").path])
        #expect(request.additionalEnvironment.isEmpty)
        #expect(request.timeout > 59.9 && request.timeout <= 60)
        #expect(measurement.duration(ofSelection: "FooTests") == 0.750)
    }

    @Test("Given a configured selection, when the baseline is measured, then it runs the same selection a mutant will")
    func baselineRunsTheConfiguredSelection() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher()

        _ = try await BaselineRunner(launcher: launcher).measure(
            selection: BundleSelection(paths: [".build/debug/BTests.xctest"], xctestSelection: "SomeSuite"),
            sandbox: Sandbox(rootURL: dir),
            timeout: 60
        )

        let request = try #require(await launcher.requests.first)

        #expect(request.arguments.dropLast() == ["xctest", "-XCTest", "SomeSuite"])
    }

    @Test(
        "Given the unmutated suite fails, when the baseline is measured, then the run aborts naming the failing tests")
    func failingBaselineAbortsNamingItsFailingTests() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = """
            Test Case '-[MyLibTests.FooTests testOne]' passed (0.001 seconds).
            Test Case '-[MyLibTests.FooTests testTwo]' failed (0.002 seconds).
            """
        let launcher = RecordingProcessLauncher(outcomes: [(exitCode: 1, output: output)])

        await #expect(throws: BaselineError.testsFailed(tests: ["MyLibTests.FooTests.testTwo"])) {
            try await BaselineRunner(launcher: launcher).measure(
                selection: BundleSelection(
                    paths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"], xctestSelection: nil
                ),
                sandbox: Sandbox(rootURL: dir),
                timeout: 60
            )
        }

        #expect(await launcher.requests.count == 1)
    }

    @Test("Given the unmutated suite does not finish in time, when the baseline is measured, then the run aborts")
    func baselineThatTimesOutAbortsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(
            outcomes: [(exitCode: SPMResultParser.timeoutExitCode, output: "")]
        )

        await #expect(throws: BaselineError.didNotFinish(seconds: 60)) {
            try await BaselineRunner(launcher: launcher).measure(
                selection: BundleSelection(paths: [".build/debug/ATests.xctest"], xctestSelection: nil),
                sandbox: Sandbox(rootURL: dir),
                timeout: 60
            )
        }
    }

    @Test(
        "Given multiple bundles, when the baseline is measured, then a later bundle only gets the timeout remaining from the run's start"
    )
    func laterBundleGetsOnlyTheRemainingTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = DelayingProcessLauncher(firstCallDelay: 0.2)

        _ = try await BaselineRunner(launcher: launcher).measure(
            selection: BundleSelection(
                paths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"], xctestSelection: nil
            ),
            sandbox: Sandbox(rootURL: dir),
            timeout: 1.0
        )

        let requests = await launcher.requests

        #expect(requests.count == 2)
        #expect(requests[0].timeout > 0.95)
        #expect(requests[0].timeout <= 1.0)
        #expect(requests[1].timeout <= 0.85)
        #expect(requests[1].timeout > 0)
    }

    @Test(
        "Given an earlier bundle consumes the whole timeout, when the baseline is measured, then the run aborts as not finished without launching the rest"
    )
    func earlierBundleExhaustingTheTimeoutAbortsWithoutLaunchingTheRest() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = DelayingProcessLauncher(firstCallDelay: 0.1)

        await #expect(throws: BaselineError.didNotFinish(seconds: 0.05)) {
            try await BaselineRunner(launcher: launcher).measure(
                selection: BundleSelection(
                    paths: [".build/debug/ATests.xctest", ".build/debug/BTests.xctest"], xctestSelection: nil
                ),
                sandbox: Sandbox(rootURL: dir),
                timeout: 0.05
            )
        }

        #expect(await launcher.requests.count == 1)
    }

    @Test("Given the unmutated suite crashes without naming a test, when measured, then the run aborts with its output")
    func crashingBaselineAbortsWithItsOutput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(outcomes: [(exitCode: 1, output: "dyld: Library not loaded")])

        await #expect(throws: BaselineError.runFailed(output: "dyld: Library not loaded")) {
            try await BaselineRunner(launcher: launcher).measure(
                selection: BundleSelection(paths: [".build/debug/ATests.xctest"], xctestSelection: nil),
                sandbox: Sandbox(rootURL: dir),
                timeout: 60
            )
        }
    }
}
