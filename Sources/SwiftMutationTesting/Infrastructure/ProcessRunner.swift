import Foundation

struct ProcessRunner: Sendable {
    /// How long a streamed launch waits, after the process it started has exited, for the last of
    /// its output to arrive before returning without it. Long enough that output still in flight is
    /// not truncated; short enough that a descendant holding the pipe open costs one pause rather
    /// than the whole run.
    static let outputGracePeriod: Double = 5

    var postTerminationCleanup: (@Sendable (Int32) -> Void)?

    /// Terminates a launched process and everything it spawned. Used for every termination the
    /// runner decides on itself: an expired timeout, a cancelled task, and a streamed run a caller
    /// asked to stop at a line it recognised.
    let killProcessTree: @Sendable (Int32) -> Void

    private struct CaptureTarget {
        let fileHandle: FileHandle
        let tempURL: URL
    }

    /// Everything a streamed launch needs while it runs: the process and the pipe it writes to, the
    /// condition that decides when to stop reading, and the flags recording why it ended.
    private struct StreamingLaunch {
        let process: Process
        let pipe: Pipe
        let stopWhen: @Sendable (String) -> Bool
        let timeout: Double
        let killedByUs: OneWayFlag
        let stoppedEarly: OneWayFlag
    }

    /// A flag that is set once and never cleared, safe to read and set from the queues Foundation
    /// runs a process's termination and readability handlers on.
    final class OneWayFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false

        var value: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }

        func mark() {
            lock.lock()
            flag = true
            lock.unlock()
        }
    }

    /// Decides when a streamed launch resumes, and lets it resume only once. Normally that is when
    /// both halves have finished — output can still arrive after the process's termination handler
    /// has run, and the exit status is not known yet when the pipe reaches end of file, so whichever
    /// half completes last resumes. `giveUpOnOutput` is the way out when the second half never
    /// comes.
    private final class StreamCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var outputFinished = false
        private var processExited = false
        private var resumed = false

        /// Records that the output pipe reached end of file. True when the caller should resume.
        func markOutputFinished() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            outputFinished = true
            return claimResume(ready: processExited)
        }

        /// Records that the process exited. True when the caller should resume.
        func markProcessExited() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            processExited = true
            return claimResume(ready: outputFinished)
        }

        /// Stops waiting for output that may never end. True when the caller should resume.
        func giveUpOnOutput() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return claimResume(ready: true)
        }

        /// Hands the single resume to the first caller that asks for it while ready.
        private func claimResume(ready: Bool) -> Bool {
            guard ready, !resumed else { return false }
            resumed = true
            return true
        }
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let killedByUs = OneWayFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startProcess(
                    process, killedByUs: killedByUs, timeout: timeout,
                    continuation: continuation
                )
            }
        } onCancel: {
            killedByUs.mark()
            killProcessTree(process.processIdentifier)
        }
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        let process = makeProcess(for: request)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        process.standardOutput = fileHandle
        process.standardError = fileHandle

        let killedByUs = OneWayFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startCapturingProcess(
                    process, killedByUs: killedByUs, timeout: request.timeout,
                    capture: CaptureTarget(fileHandle: fileHandle, tempURL: tempURL),
                    continuation: continuation
                )
            }
        } onCancel: {
            killedByUs.mark()
            killProcessTree(process.processIdentifier)
        }
    }

    func launchStreaming(
        _ request: ProcessRequest,
        stopWhen: @escaping @Sendable (String) -> Bool
    ) async throws -> StreamedProcessResult {
        let process = makeProcess(for: request)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let killedByUs = OneWayFlag()
        let stoppedEarly = OneWayFlag()

        let launch = StreamingLaunch(
            process: process, pipe: pipe, stopWhen: stopWhen, timeout: request.timeout,
            killedByUs: killedByUs, stoppedEarly: stoppedEarly
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startStreamingProcess(launch, continuation: continuation)
            }
        } onCancel: {
            killedByUs.mark()
            killProcessTree(process.processIdentifier)
        }
    }

    private func makeProcess(for request: ProcessRequest) -> Process {
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectoryURL

        if let environment = request.environment {
            process.environment = environment
        }

        if !request.additionalEnvironment.isEmpty {
            var env = process.environment ?? ProcessInfo.processInfo.environment
            for (key, value) in request.additionalEnvironment {
                env[key] = value
            }
            process.environment = env
        }

        return process
    }

    private func startProcess(
        _ process: Process,
        killedByUs: OneWayFlag,
        timeout: Double,
        continuation: CheckedContinuation<Int32, any Error>
    ) {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            killedByUs.mark()
            killProcessTree(process.processIdentifier)
        }

        process.terminationHandler = { proc in
            timeoutTask.cancel()
            postTerminationCleanup?(proc.processIdentifier)
            let exitCode: Int32 = killedByUs.value ? -1 : proc.terminationStatus
            continuation.resume(returning: exitCode)
        }

        do {
            try process.run()
            setpgid(process.processIdentifier, process.processIdentifier)
            // onCancel can run concurrently with this method, even before process.run() has
            // assigned a real pid — its own killProcessTree call is then a no-op against pid 0.
            // Re-checking here, now that the pid is real, closes that window.
            if killedByUs.value {
                killProcessTree(process.processIdentifier)
            }
        } catch {
            timeoutTask.cancel()
            continuation.resume(throwing: error)
        }
    }

    private func startCapturingProcess(
        _ process: Process,
        killedByUs: OneWayFlag,
        timeout: Double,
        capture: CaptureTarget,
        continuation: CheckedContinuation<(exitCode: Int32, output: String), any Error>
    ) {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            killedByUs.mark()
            killProcessTree(process.processIdentifier)
        }

        process.terminationHandler = { terminated in
            timeoutTask.cancel()
            postTerminationCleanup?(terminated.processIdentifier)
            capture.fileHandle.closeFile()
            let output = (try? String(contentsOf: capture.tempURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: capture.tempURL)
            let exitCode: Int32 = killedByUs.value ? -1 : terminated.terminationStatus
            continuation.resume(returning: (exitCode: exitCode, output: output))
        }

        do {
            try process.run()
            setpgid(process.processIdentifier, process.processIdentifier)
            // onCancel can run concurrently with this method, even before process.run() has
            // assigned a real pid — its own killProcessTree call is then a no-op against pid 0.
            // Re-checking here, now that the pid is real, closes that window.
            if killedByUs.value {
                killProcessTree(process.processIdentifier)
            }
        } catch {
            timeoutTask.cancel()
            capture.fileHandle.closeFile()
            try? FileManager.default.removeItem(at: capture.tempURL)
            continuation.resume(throwing: error)
        }
    }

    /// Reads the process's output as it is produced, offering each completed line to `stopWhen`,
    /// and kills the process tree at the first line accepted. Output written before the kill is
    /// kept: the caller's verdict is in it.
    private func startStreamingProcess(
        _ launch: StreamingLaunch,
        continuation: CheckedContinuation<StreamedProcessResult, any Error>
    ) {
        let process = launch.process
        let stoppedEarly = launch.stoppedEarly
        let stopWhen = launch.stopWhen
        let lines = OutputLineBuffer()
        let completion = StreamCompletion()
        let reader = launch.pipe.fileHandleForReading

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(launch.timeout))
            launch.killedByUs.mark()
            killProcessTree(process.processIdentifier)
        }

        let finish = makeFinish(launch, reader: reader, lines: lines, continuation: continuation)

        reader.readabilityHandler = { handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                if completion.markOutputFinished() { finish() }
                return
            }

            let completed = lines.append(data)

            guard !stoppedEarly.value, completed.contains(where: stopWhen) else { return }

            stoppedEarly.mark()
            killProcessTree(process.processIdentifier)
        }

        process.terminationHandler = { terminated in
            timeoutTask.cancel()
            postTerminationCleanup?(terminated.processIdentifier)

            // Output outliving the process means something that inherited the pipe is still
            // holding it open, and that may never end — hence the grace rather than a plain wait.
            if completion.markProcessExited() {
                finish()
            } else {
                armOutputGrace(completion, then: finish)
            }
        }

        do {
            try process.run()
            setpgid(process.processIdentifier, process.processIdentifier)
            // onCancel can run concurrently with this method, even before process.run() has
            // assigned a real pid — its own killProcessTree call is then a no-op against pid 0.
            // Re-checking here, now that the pid is real, closes that window.
            if launch.killedByUs.value {
                killProcessTree(process.processIdentifier)
            }
        } catch {
            timeoutTask.cancel()
            reader.readabilityHandler = nil
            continuation.resume(throwing: error)
        }
    }

    /// The single resume of a streamed launch: stops reading, then reports what was read. A run the
    /// runner killed on its timeout reports `-1`, as the other launches do; a run stopped at a
    /// matching line reports the status the signal that stopped it produced, and says so through
    /// `stoppedEarly` so the caller knows not to read a verdict into it.
    private func makeFinish(
        _ launch: StreamingLaunch,
        reader: FileHandle,
        lines: OutputLineBuffer,
        continuation: CheckedContinuation<StreamedProcessResult, any Error>
    ) -> @Sendable () -> Void {
        {
            reader.readabilityHandler = nil
            continuation.resume(
                returning: StreamedProcessResult(
                    exitCode: launch.killedByUs.value ? -1 : launch.process.terminationStatus,
                    output: lines.output,
                    stoppedEarly: launch.stoppedEarly.value
                )
            )
        }
    }

    /// Gives output still arriving after the process exited a bounded moment to end, then resumes
    /// the launch with what was read.
    ///
    /// A descendant that left the process group before the root exited keeps the pipe's write end
    /// open and is beyond every signal that remains: the group signal never covered it, and the
    /// parent-pid walk `killProcessTree` depends on cannot find it once the root has been reaped
    /// and its survivors reparented to launchd. End of file may therefore never come, and waiting
    /// for it would hang the launch — and with it the worker running that mutant — for good.
    /// Partial output a caller can still reach a verdict from beats a launch that never returns.
    private func armOutputGrace(
        _ completion: StreamCompletion,
        then finish: @escaping @Sendable () -> Void
    ) {
        Task {
            try? await Task.sleep(for: .seconds(Self.outputGracePeriod))
            if completion.giveUpOnOutput() { finish() }
        }
    }

}
