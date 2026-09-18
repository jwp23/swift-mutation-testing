import Foundation

/// The sandbox roots this run owns. Module scope because the signal path has to reach them with
/// no Swift context to capture; every access goes through `registryLock`.
nonisolated(unsafe) private var activeSandboxRoots: [URL] = []
private let registryLock = NSLock()

/// Write end of the self-pipe the signal handler notifies on. Assigned once by
/// `installSignalHandlers` before the handler that reads it exists, and never reassigned.
nonisolated(unsafe) private var signalNotificationWriter: Int32 = -1

nonisolated(unsafe) var sandboxCleanerExitHandler: @convention(c) (Int32) -> Void = { code in _exit(code) }

/// Fires after each pass of `cleanupActiveSandboxes` has removed what it drained, which is the
/// window a worker registering its sandbox concurrently lands in. Tests register a straggler here;
/// it is `nil` in a real run.
nonisolated(unsafe) var sandboxRemovalPassCompletedHook: (@Sendable () -> Void)?

/// Does nothing that is unsafe to do in signal context: `write(2)` is async-signal-safe, the byte
/// it sends lives on the stack, and `errno` is restored so the interrupted code cannot observe the
/// signal. Removing the sandboxes needs `FileManager` and the registry lock, neither of which may
/// run here — the watcher thread woken by this byte does that instead.
private func handleSignal(_: Int32) {
    let savedErrno = errno
    var notification: UInt8 = 1
    _ = write(signalNotificationWriter, &notification, 1)
    errno = savedErrno
}

enum SandboxCleaner {

    private static let prefix = "xmr-"

    /// Removes every sandbox registered for this run. A run holds one sandbox per worker, so all
    /// of them have to go when the run is interrupted.
    ///
    /// Draining repeats until a pass finds the registry empty. A worker registering its sandbox
    /// while the previous pass was deleting would otherwise leave that root sitting in a registry
    /// nothing visits again before the process exits.
    ///
    /// One narrower window stays open: a registration landing after the final empty pass, in the
    /// gap before `sandboxCleanerExitHandler` ends the process, is still missed. That sandbox is
    /// reclaimed by the `removeOrphaned` sweep the next run starts with, the same safety net the
    /// whole-registry `deregister()` relies on.
    static func cleanupActiveSandboxes() {
        var roots = takeActiveSandboxRoots()

        while !roots.isEmpty {
            for root in roots {
                try? FileManager.default.removeItem(at: root)
            }
            sandboxRemovalPassCompletedHook?()
            roots = takeActiveSandboxRoots()
        }
    }

    /// Sweeps under the sandbox lock so enumeration, liveness checks and deletion cannot overlap
    /// another process creating a sandbox before it has recorded its owner pid.
    static func removeOrphaned(in directory: URL = FileManager.default.temporaryDirectory) {
        // If the lock can't be acquired, skip this sweep entirely rather than falling back to
        // scanning unlocked — that would reopen the exact race the lock exists to close.
        try? SandboxDirectoryLock.withExclusiveLock(in: directory) {
            guard
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
            else { return }

            for url in contents where url.lastPathComponent.hasPrefix(prefix) {
                if !isOwnedByLiveProcess(url) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// A sandbox with no owner-pid record (e.g. left over from a version predating this
    /// check, or a crash between `mkdir` and writing the pid file) is treated as orphaned
    /// and removed, matching the sweep's original unconditional behavior for such cases.
    private static func isOwnedByLiveProcess(_ sandboxURL: URL) -> Bool {
        let pidFile = sandboxURL.appendingPathComponent(SandboxFactory.ownerPidFileName)
        guard
            let contents = try? String(contentsOf: pidFile, encoding: .utf8),
            let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
            pid > 0
        else { return false }

        return kill(pid, 0) == 0 || errno != ESRCH
    }

    static func register(_ sandbox: Sandbox) {
        registryLock.lock()
        defer { registryLock.unlock() }
        activeSandboxRoots.append(sandbox.rootURL)
    }

    static func deregister() {
        _ = takeActiveSandboxRoots()
    }

    /// Installs the `SIGINT`/`SIGTERM` handlers and starts the thread that does the cleanup they
    /// ask for. Calling it more than once keeps the handlers and the watcher already in place.
    ///
    /// If the notification pipe cannot be created the handlers are left at their default
    /// disposition: an interrupted run then dies without cleaning up, and its sandboxes are
    /// reclaimed by the `removeOrphaned` sweep the next run starts with.
    static func installSignalHandlers() {
        guard signalNotificationWriter < 0 else { return }

        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { return }
        let reader = descriptors[0]
        let writer = descriptors[1]

        // Keep the pipe out of the processes the run spawns, and keep the handler from ever
        // blocking on a full pipe when signals arrive faster than the watcher drains them. If any
        // of that configuration fails, fall back to the same left-at-default-disposition path as
        // a failed `pipe()` above rather than risk a handler that can block.
        guard
            fcntl(reader, F_SETFD, FD_CLOEXEC) != -1,
            fcntl(writer, F_SETFD, FD_CLOEXEC) != -1,
            fcntl(writer, F_SETFL, O_NONBLOCK) != -1
        else {
            close(reader)
            close(writer)
            return
        }
        signalNotificationWriter = writer

        let watcher = Thread { cleanUpOnSignalNotification(from: reader) }
        watcher.name = "sandbox-cleaner-signal-watcher"
        watcher.start()

        signal(SIGINT, handleSignal)
        signal(SIGTERM, handleSignal)
    }

    /// Waits on the notification pipe and runs the interrupted run's cleanup on this ordinary
    /// thread, where `FileManager` and the registry lock are legal. Returns when the pipe can
    /// deliver nothing further. It stays in the loop after the exit handler returns because only
    /// a test supplies one that does — in a real run `_exit` ends the process here.
    static func cleanUpOnSignalNotification(from descriptor: Int32) {
        while awaitNotification(from: descriptor) {
            cleanupActiveSandboxes()
            sandboxCleanerExitHandler(1)
        }
    }

    private static func awaitNotification(from descriptor: Int32) -> Bool {
        var notification: UInt8 = 0

        while true {
            let count = read(descriptor, &notification, 1)
            if count == 1 { return true }
            // A read of 0 is the write end closing and anything else is an unrecoverable pipe
            // error; only an interrupted read is worth retrying.
            guard count < 0, errno == EINTR else { return false }
        }
    }

    /// Empties the registry and hands back what it held, so the removals happen off the lock and
    /// two callers racing — the watcher thread and a run tearing itself down — can never try to
    /// remove the same sandbox root.
    private static func takeActiveSandboxRoots() -> [URL] {
        registryLock.lock()
        defer { registryLock.unlock() }
        let roots = activeSandboxRoots
        activeSandboxRoots = []

        return roots
    }
}
