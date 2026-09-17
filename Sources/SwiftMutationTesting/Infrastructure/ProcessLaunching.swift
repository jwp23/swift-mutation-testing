import Foundation

protocol ProcessLaunching: Sendable {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String)

    /// Runs the process, handing every complete output line to `stopWhen` as it is produced, and
    /// terminates the process and its descendants at the first line `stopWhen` accepts. A caller
    /// that can reach its verdict from partial output does not wait out the rest of the run.
    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult
}

extension ProcessLaunching {
    /// A launcher that produces its output in one piece has nothing to stream: the process runs to
    /// completion, no line is ever offered to `stopWhen`, and nothing is stopped early.
    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult {
        let captured = try await launchCapturing(request)

        return StreamedProcessResult(
            exitCode: captured.exitCode, output: captured.output, stoppedEarly: false
        )
    }
}

/// A `ProcessLaunching` conformer backed by a `ProcessRunner`. Supplies the shared
/// launch/launchCapturing forwarding so conformers only need to configure their runner.
protocol RunnerBackedProcessLaunching: ProcessLaunching {
    func makeRunner() -> ProcessRunner
}

extension RunnerBackedProcessLaunching {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        try await makeRunner().launch(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        try await makeRunner().launchCapturing(request)
    }

    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult {
        try await makeRunner().launchStreaming(request, stopWhen: stopWhen)
    }
}
