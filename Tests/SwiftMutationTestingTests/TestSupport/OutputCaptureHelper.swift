import Foundation

/// Serializes the stdout/stderr redirect-capture-restore sequences below. All three functions
/// retarget process-wide file descriptors (`STDOUT_FILENO` / `STDERR_FILENO`); without this gate,
/// two overlapping calls — from concurrent tests, or async and sync capture running together —
/// can interleave their `dup2`/restore steps and route output to, or restore, the wrong
/// descriptor. The gate is therefore held across the whole sequence, including the async
/// functions' `await block()`.
///
/// A semaphore backs it rather than a lock because holding it spans a suspension point. A mutex
/// (`NSLock`, `os_unfair_lock`, `Mutex`) must be released by the thread that acquired it, but a
/// task that suspends inside `block()` can resume on a different thread and release from there.
/// `DispatchSemaphore` has no such thread affinity: any thread may `signal()` what another
/// `wait()`ed on.
///
/// The async entry point is `acquireWithoutBlockingCaller()` rather than a direct `wait()`:
/// blocking a cooperative-pool thread while waiting deadlocks the pool once enough captures
/// overlap, because the holder — suspended inside its own `block()` — then has no thread left to
/// resume on. Waiting on a global-queue thread instead leaves the caller merely suspended.
///
/// That deadlock avoidance belongs to the async entry point alone. `acquire()` blocks its calling
/// thread outright, so enough synchronous waiters contending with a suspended async holder will
/// starve the pool in exactly the way described above. `captureOutputSync` is its only caller and
/// is used from a single site, well below any such threshold; a synchronous caller that cannot
/// bound its own concurrency against suspended async holders must not use it.
///
/// The gate is not recursive: a capture block that starts another capture would deadlock.
private final class OutputCaptureGate: Sendable {
    static let shared = OutputCaptureGate()

    private let semaphore = DispatchSemaphore(value: 1)

    private init() {}

    /// Acquires the gate from a synchronous context, blocking the calling thread until it is free.
    /// Unlike `acquireWithoutBlockingCaller()`, this offers no protection against starving the
    /// cooperative pool — see the type's documentation.
    func acquire() { semaphore.wait() }

    /// Acquires the gate from an async context, suspending the caller instead of blocking its thread.
    func acquireWithoutBlockingCaller() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [semaphore] in
                semaphore.wait()
                continuation.resume()
            }
        }
    }

    /// Releases the gate. Safe to call from a thread other than the one that acquired it.
    func release() { semaphore.signal() }
}

func captureOutput(_ block: () async -> Void) async -> String {
    await OutputCaptureGate.shared.acquireWithoutBlockingCaller()
    defer { OutputCaptureGate.shared.release() }

    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    await block()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func captureOutputSync(_ block: () -> Void) -> String {
    OutputCaptureGate.shared.acquire()
    defer { OutputCaptureGate.shared.release() }

    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    block()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func captureStandardError(_ block: () async throws -> Void) async throws -> String {
    await OutputCaptureGate.shared.acquireWithoutBlockingCaller()
    defer { OutputCaptureGate.shared.release() }

    let pipe = Pipe()
    let originalStderr = dup(STDERR_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

    do {
        try await block()
    } catch {
        fflush(stderr)
        dup2(originalStderr, STDERR_FILENO)
        close(originalStderr)
        pipe.fileHandleForWriting.closeFile()
        throw error
    }

    fflush(stderr)
    dup2(originalStderr, STDERR_FILENO)
    close(originalStderr)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
