import Foundation

/// Interprocess exclusive lock serializing sandbox creation against the orphan sweep.
///
/// A sandbox directory exists briefly before its `.owner-pid` file is written, and a sweep that
/// enumerates during that window sees an unowned directory and deletes a live run's sandbox.
/// Creators hold this lock from directory creation through the pid write, and the sweep holds it
/// across enumeration, liveness checks and deletion, so the two can never interleave.
///
/// The lock is an advisory `flock(2)` on a file that sits beside the sandboxes, not inside any one
/// of them. The kernel drops it when the holding process exits, so a crash cannot strand it.
enum SandboxDirectoryLock {

    static let fileName = ".swift-mutation-testing-sandbox.lock"

    /// Thrown when the sandbox lock cannot be acquired — the lock file could not be opened, or
    /// the underlying `flock(2)` call failed for a reason other than a retryable interruption.
    struct AcquisitionFailed: Error {}

    /// Runs `body` while holding the exclusive lock for `directory`.
    ///
    /// Throws `AcquisitionFailed` rather than running `body` unlocked: a read-only temp
    /// directory, one owned by another user, or a `flock` failure would otherwise reopen the
    /// exact creation/sweep race this lock exists to close. `SandboxFactory.makeSandboxRoot`
    /// propagates this error (sandbox creation fails outright); `SandboxCleaner.removeOrphaned`
    /// is nonthrowing and catches it to skip the sweep for this pass instead.
    static func withExclusiveLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        guard let descriptor = openLockFile(in: directory) else { throw AcquisitionFailed() }

        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        while true {
            if flock(descriptor, LOCK_EX) == 0 { break }
            guard errno == EINTR else { throw AcquisitionFailed() }
        }

        return try body()
    }

    private static func openLockFile(in directory: URL) -> Int32? {
        let path = directory.appendingPathComponent(fileName).path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        return descriptor < 0 ? nil : descriptor
    }
}
