import Foundation

/// The one run of the unmutated suite every mutant is judged against.
///
/// It runs the bundles a mutant's run does, the way a mutant's run does, with no mutant selected
/// — the schema falls through to its `default` branch and the original code executes. Two things
/// come out of that: proof the suite passes before anything is mutated, and how long its tests
/// take, which is the scale a mutant's timeout is set on.
struct BaselineRunner: Sendable {
    let launcher: any ProcessLaunching

    func measure(
        selection: BundleSelection,
        sandbox: Sandbox,
        timeout: Double
    ) async throws -> BaselineMeasurement {
        var output = ""
        var exitCode: Int32 = 0
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)

        for bundlePath in selection.paths {
            let remaining = deadline.timeIntervalSinceNow

            guard remaining > 0 else { throw BaselineError.didNotFinish(seconds: timeout) }

            let captured = try await launcher.launchCapturing(
                request(bundlePath: bundlePath, selection: selection, sandbox: sandbox, timeout: remaining)
            )

            output += output.isEmpty ? captured.output : "\n" + captured.output
            exitCode = captured.exitCode

            if exitCode != 0 { break }
        }

        let parsed = BaselineOutputParser().parse(output)

        if let failure = failure(exitCode: exitCode, output: output, parsed: parsed, timeout: timeout) {
            throw failure
        }

        return BaselineMeasurement(
            totalDuration: Date().timeIntervalSince(start), testDurations: parsed.testDurations
        )
    }

    /// Why this run cannot serve as a baseline, or `nil` when the suite passed. A run that named
    /// the tests it failed is reported by those names; one that died without naming any is
    /// reported by what it printed, or by the timeout that stopped it.
    private func failure(
        exitCode: Int32,
        output: String,
        parsed: BaselineOutputParser.Result,
        timeout: Double
    ) -> BaselineError? {
        if !parsed.failingTests.isEmpty { return .testsFailed(tests: parsed.failingTests) }
        if exitCode == SPMResultParser.timeoutExitCode { return .didNotFinish(seconds: timeout) }
        if exitCode != 0 { return .runFailed(output: output) }

        return nil
    }

    private func request(
        bundlePath: String,
        selection: BundleSelection,
        sandbox: Sandbox,
        timeout: Double
    ) -> ProcessRequest {
        var arguments = ["xctest"]

        if let xctestSelection = selection.xctestSelection {
            arguments += ["-XCTest", xctestSelection]
        }

        arguments.append(sandbox.rootURL.appendingPathComponent(bundlePath).path)

        return ProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: sandbox.rootURL,
            timeout: timeout
        )
    }
}
