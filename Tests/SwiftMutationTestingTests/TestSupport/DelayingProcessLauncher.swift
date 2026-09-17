import Foundation

@testable import SwiftMutationTesting

/// Records every capturing launch like `RecordingProcessLauncher`, but sleeps for a configured
/// duration before returning from its first call — the delay a real baseline bundle's own run
/// time introduces between when the run starts and when a later bundle is launched.
actor DelayingProcessLauncher: ProcessLaunching {

    init(firstCallDelay: TimeInterval, exitCode: Int32 = 0, output: String = "") {
        self.firstCallDelay = firstCallDelay
        self.exitCode = exitCode
        self.output = output
    }

    private(set) var requests: [ProcessRequest] = []

    private let firstCallDelay: TimeInterval
    private let exitCode: Int32
    private let output: String

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

        if requests.count == 1 {
            try await Task.sleep(nanoseconds: UInt64(firstCallDelay * 1_000_000_000))
        }

        return (exitCode: exitCode, output: output)
    }

    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult {
        let captured = try await launchCapturing(request)

        return StreamedProcessResult(exitCode: captured.exitCode, output: captured.output, stoppedEarly: false)
    }
}
