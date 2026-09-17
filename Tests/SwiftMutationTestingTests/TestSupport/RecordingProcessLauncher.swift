import Foundation

@testable import SwiftMutationTesting

/// Records every capturing launch so tests can assert on the command, environment and working
/// directory a stage asked for. Outcomes are returned in order, the last one repeating.
actor RecordingProcessLauncher: ProcessLaunching {

    init(outcomes: [(exitCode: Int32, output: String)] = [(exitCode: 0, output: "")]) {
        self.outcomes = outcomes
    }

    private(set) var requests: [ProcessRequest] = []

    /// Every line a streamed launch offered to its stop condition, in the order it was produced.
    private(set) var streamedLines: [String] = []

    /// Exit status the kernel reports for a process terminated by `SIGTERM`, which is how a run
    /// stopped at its first failing test ends.
    private static let terminatedBySignalExitCode: Int32 = 15

    private let outcomes: [(exitCode: Int32, output: String)]

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        requests.append(request)
        return outcomes[min(requests.count - 1, outcomes.count - 1)]
    }

    /// Replays the canned output a line at a time, the way a real run prints it. A line the stop
    /// condition accepts ends the launch there: the caller gets only the output up to that line,
    /// and the exit status of a process killed mid-run rather than the canned one.
    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult {
        requests.append(request)
        let outcome = outcomes[min(requests.count - 1, outcomes.count - 1)]
        var produced: [String] = []

        for line in outcome.output.components(separatedBy: "\n") {
            produced.append(line)
            streamedLines.append(line)

            guard stopWhen(line) else { continue }

            return StreamedProcessResult(
                exitCode: Self.terminatedBySignalExitCode,
                output: produced.joined(separator: "\n"),
                stoppedEarly: true
            )
        }

        return StreamedProcessResult(
            exitCode: outcome.exitCode, output: outcome.output, stoppedEarly: false
        )
    }
}
