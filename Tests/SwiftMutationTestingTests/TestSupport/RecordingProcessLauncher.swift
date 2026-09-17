import Foundation

@testable import SwiftMutationTesting

/// Records every capturing launch so tests can assert on the command, environment and working
/// directory a stage asked for. Outcomes are returned in order, the last one repeating.
actor RecordingProcessLauncher: ProcessLaunching {

    init(outcomes: [(exitCode: Int32, output: String)] = [(exitCode: 0, output: "")]) {
        self.outcomes = outcomes
    }

    private(set) var requests: [ProcessRequest] = []

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
}
