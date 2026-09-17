import Foundation

@testable import SwiftMutationTesting

/// Builds successfully, then answers the test-bundle runs: the unmutated baseline run — the one
/// launched with no mutant selected — gets the canned outcome, while every run with a mutant
/// selected passes. Records the mutant runs so a test can assert on the timeout each was given.
actor SPMBaselineMock: ProcessLaunching {

    init(baselineExitCode: Int32 = 0, baselineOutput: String = "") {
        self.baselineExitCode = baselineExitCode
        self.baselineOutput = baselineOutput
    }

    private(set) var mutantRequests: [ProcessRequest] = []

    private(set) var baselineRequests: [ProcessRequest] = []

    private let baselineExitCode: Int32
    private let baselineOutput: String

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
        writeMockedTestBundle(for: request)

        guard request.arguments.first == "xctest" else { return (0, "") }

        guard request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] == nil else {
            mutantRequests.append(request)
            return (0, "")
        }

        baselineRequests.append(request)

        return (baselineExitCode, baselineOutput)
    }
}
