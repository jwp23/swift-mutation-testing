import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxCleaner registry concurrency")
struct SandboxCleanerRegistryRaceTests {

    @Test("Given concurrent register and cleanup, when they interleave, then no sandbox root is lost or freed twice")
    func concurrentRegisterAndCleanupStaysConsistent() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            let root = baseDir.appendingPathComponent("xmr-\(index)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            SandboxCleaner.register(Sandbox(rootURL: root))
            SandboxCleaner.cleanupActiveSandboxes()
        }

        SandboxCleaner.cleanupActiveSandboxes()

        let remaining = try FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil)
        #expect(remaining.isEmpty)
    }

    @Test(
        "Given a sandbox registered after the registry is drained, when cleanup runs, then the straggler is removed too"
    )
    func cleanupRemovesSandboxRegisteredWhileItRuns() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let firstRoot = baseDir.appendingPathComponent("xmr-first")
        let stragglerRoot = baseDir.appendingPathComponent("xmr-straggler")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stragglerRoot, withIntermediateDirectories: true)

        SandboxCleaner.register(Sandbox(rootURL: firstRoot))
        defer { SandboxCleaner.deregister() }

        let straggler = StragglerRegistration(sandbox: Sandbox(rootURL: stragglerRoot))
        sandboxRemovalPassCompletedHook = { straggler.registerOnce() }
        defer { sandboxRemovalPassCompletedHook = nil }

        SandboxCleaner.cleanupActiveSandboxes()

        #expect(!FileManager.default.fileExists(atPath: firstRoot.path))
        #expect(!FileManager.default.fileExists(atPath: stragglerRoot.path))
    }

    @Test(
        "Given a sandbox registered after the registry is drained, when the watcher answers a signal, then it is removed before the exit"
    )
    func signalCleanupRemovesSandboxRegisteredWhileItRuns() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let firstRoot = baseDir.appendingPathComponent("xmr-signal-first")
        let stragglerRoot = baseDir.appendingPathComponent("xmr-signal-straggler")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stragglerRoot, withIntermediateDirectories: true)

        SandboxCleaner.register(Sandbox(rootURL: firstRoot))
        defer { SandboxCleaner.deregister() }

        let straggler = StragglerRegistration(sandbox: Sandbox(rootURL: stragglerRoot))
        sandboxRemovalPassCompletedHook = { straggler.registerOnce() }
        defer { sandboxRemovalPassCompletedHook = nil }

        let previousExit = sandboxCleanerExitHandler
        watchRootAtExit(stragglerRoot.path)
        sandboxCleanerExitHandler = { _ in recordWatchedRootAtExit() }
        defer { sandboxCleanerExitHandler = previousExit }

        var descriptors: [Int32] = [-1, -1]
        _ = pipe(&descriptors)
        var notification: UInt8 = 1
        _ = write(descriptors[1], &notification, 1)
        close(descriptors[1])
        defer { close(descriptors[0]) }

        SandboxCleaner.cleanUpOnSignalNotification(from: descriptors[0])

        // What the exit handler saw is what a real run would have left behind when `_exit` fired.
        #expect(watchedRootExistedAtExit() == false)
        #expect(!FileManager.default.fileExists(atPath: firstRoot.path))
    }
}

/// Registers a sandbox the first time a removal pass completes, standing in for a worker that
/// registers its sandbox in the window between the registry being drained and the process exiting.
/// It registers once only, so cleanup still reaches an empty pass and returns.
private final class StragglerRegistration: @unchecked Sendable {

    init(sandbox: Sandbox) {
        self.sandbox = sandbox
    }

    func registerOnce() {
        let shouldRegister = lock.withLock {
            defer { registered = true }

            return !registered
        }

        if shouldRegister { SandboxCleaner.register(sandbox) }
    }

    private let lock = NSLock()
    private let sandbox: Sandbox
    private var registered = false
}

private let exitSurveyLock = NSLock()
nonisolated(unsafe) private var watchedRootAtExit = ""
nonisolated(unsafe) private var watchedRootPresentAtExit: Bool?

private func watchRootAtExit(_ path: String) {
    exitSurveyLock.withLock {
        watchedRootAtExit = path
        watchedRootPresentAtExit = nil
    }
}

/// Records whether the watched sandbox root was still on disk when the exit handler ran. A
/// `@convention(c)` exit stub cannot capture the test's state, so the answer goes through file
/// scope.
private func recordWatchedRootAtExit() {
    let path = exitSurveyLock.withLock { watchedRootAtExit }
    let exists = FileManager.default.fileExists(atPath: path)
    exitSurveyLock.withLock { watchedRootPresentAtExit = exists }
}

private func watchedRootExistedAtExit() -> Bool? {
    exitSurveyLock.withLock { watchedRootPresentAtExit }
}
