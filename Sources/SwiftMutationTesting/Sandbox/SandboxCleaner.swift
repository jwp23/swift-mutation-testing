import Foundation

nonisolated(unsafe) private var activeSandboxPaths: [UnsafeMutablePointer<CChar>] = []
nonisolated(unsafe) var sandboxCleanerExitHandler: @convention(c) (Int32) -> Void = { code in _exit(code) }

private func handleSignal(_: Int32) {
    SandboxCleaner.cleanupActiveSandboxes()
    sandboxCleanerExitHandler(1)
}

enum SandboxCleaner {

    private static let prefix = "xmr-"

    /// Removes every sandbox registered for this run. A run holds one sandbox per worker, so all
    /// of them have to go when the run is interrupted.
    static func cleanupActiveSandboxes() {
        for path in activeSandboxPaths {
            let url = URL(fileURLWithPath: String(cString: path))
            try? FileManager.default.removeItem(at: url)
            path.deallocate()
        }
        activeSandboxPaths = []
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
        let path = sandbox.rootURL.path
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: path.utf8.count + 1)
        _ = path.withCString { strcpy(buffer, $0) }
        activeSandboxPaths.append(buffer)
    }

    static func deregister() {
        for path in activeSandboxPaths {
            path.deallocate()
        }
        activeSandboxPaths = []
    }

    static func installSignalHandlers() {
        signal(SIGINT, handleSignal)
        signal(SIGTERM, handleSignal)
    }
}
