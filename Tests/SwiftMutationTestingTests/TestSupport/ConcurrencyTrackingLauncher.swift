import Foundation

@testable import SwiftMutationTesting

/// Keeps each launch in flight briefly and records how many were in flight at once, so a test can
/// tell workers that really run side by side from ones that are serialized behind each other.
actor ConcurrencyTrackingLauncher: ProcessLaunching {

    private(set) var peakInFlight = 0

    private var inFlight = 0

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
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        try? await Task.sleep(for: .milliseconds(150))
        inFlight -= 1

        return (exitCode: 0, output: "")
    }
}
