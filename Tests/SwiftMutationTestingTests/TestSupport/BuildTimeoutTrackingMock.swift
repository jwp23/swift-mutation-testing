import Foundation

@testable import SwiftMutationTesting

/// A mock process launcher that tracks all build-related timeouts passed to it.
/// Used to verify that build operations receive the correct timeout value.
actor BuildTimeoutTrackingMock: ProcessLaunching {
    /// The timeout each `swift build` or `xcodebuild build` request was given, in call order.
    private(set) var buildTimeouts: [Double] = []

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

        // Track build operations only, not test operations
        // - swift build / swift build --build-tests = build
        // - xcodebuild build-for-testing = build
        let isBuild = (
            (request.executableURL.lastPathComponent == "swift" && request.arguments.first == "build") ||
            (request.executableURL.lastPathComponent == "xcodebuild" && request.arguments.first == "build-for-testing")
        )
        if isBuild {
            buildTimeouts.append(request.timeout)
            return (0, "")
        }

        return (0, "")
    }
}
