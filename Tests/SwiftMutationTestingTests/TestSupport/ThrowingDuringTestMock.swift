import Foundation

@testable import SwiftMutationTesting

/// Builds successfully, then throws when a mutant's test bundle is launched.
actor ThrowingDuringTestMock: ProcessLaunching {

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        writeMockedTestBundle(for: request)

        if request.arguments.first == "xctest" {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return (0, "")
    }
}
