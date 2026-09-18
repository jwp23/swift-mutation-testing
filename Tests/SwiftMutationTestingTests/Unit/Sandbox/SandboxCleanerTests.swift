import Foundation
import Testing

@testable import SwiftMutationTesting

private let exitRecordLock = NSLock()
nonisolated(unsafe) private var capturedExitCodes: [Int32] = []

/// The watcher thread calls this, so the record it writes is read back under the same lock.
private func stubExitHandler(_ code: Int32) {
    exitRecordLock.lock()
    capturedExitCodes.append(code)
    exitRecordLock.unlock()
}

private func recordedExitCodes() -> [Int32] {
    exitRecordLock.lock()
    defer { exitRecordLock.unlock() }

    return capturedExitCodes
}

private func resetRecordedExitCodes() {
    exitRecordLock.lock()
    capturedExitCodes = []
    exitRecordLock.unlock()
}

/// Waits for the watcher thread to record `count` exit codes, giving up after `timeout` seconds so
/// a handler that never fires fails the expectation instead of hanging the suite.
private func waitForRecordedExitCodes(count: Int, timeout: TimeInterval = 5) -> [Int32] {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        let codes = recordedExitCodes()
        if codes.count >= count { return codes }
        usleep(1000)
    }

    return recordedExitCodes()
}

/// A notification pipe primed with `notifications` bytes and closed for writing, so
/// `cleanUpOnSignalNotification` handles exactly those and then returns instead of blocking.
private func makePrimedNotificationPipe(notifications: Int) -> Int32 {
    var descriptors: [Int32] = [-1, -1]
    _ = pipe(&descriptors)

    for _ in 0 ..< notifications {
        var notification: UInt8 = 1
        _ = write(descriptors[1], &notification, 1)
    }
    close(descriptors[1])

    return descriptors[0]
}

@Suite("SandboxCleaner")
struct SandboxCleanerTests {

    @Test("Given orphaned xmr directories, when removeOrphaned called, then all are deleted")
    func removeOrphanedDeletesXmrDirectories() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let orphan1 = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        let orphan2 = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: orphan1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan2, withIntermediateDirectories: true)
        try "content".write(
            to: orphan1.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: orphan1.path))
        #expect(!FileManager.default.fileExists(atPath: orphan2.path))
    }

    @Test("Given non-xmr directories, when removeOrphaned called, then they are preserved")
    func removeOrphanedPreservesNonXmrDirectories() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let unrelated = baseDir.appendingPathComponent("other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("Given orphaned xmr directories with nested content, when removeOrphaned called, then entire tree is removed")
    func removeOrphanedDeletesNestedContent() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let orphan = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        let nestedDir = orphan.appendingPathComponent("Sources/MyLib")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "nested".write(
            to: nestedDir.appendingPathComponent("File.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test("Given empty directory, when removeOrphaned called, then no error occurs")
    func removeOrphanedOnEmptyDirectoryIsNoOp() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        SandboxCleaner.removeOrphaned(in: baseDir)
    }

    @Test("Given mixed xmr and non-xmr entries, when removeOrphaned called, then only xmr are removed")
    func removeOrphanedDeletesOnlyXmrEntries() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let xmrDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        let otherDir = baseDir.appendingPathComponent("something-else")
        let regularFile = baseDir.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: xmrDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try "data".write(to: regularFile, atomically: true, encoding: .utf8)

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: xmrDir.path))
        #expect(FileManager.default.fileExists(atPath: otherDir.path))
        #expect(FileManager.default.fileExists(atPath: regularFile.path))
    }

    @Test("Given xmr directory owned by a live process, when removeOrphaned called, then it is preserved")
    func removeOrphanedPreservesLiveOwnerDirectory() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let liveProcess = Process()
        liveProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        liveProcess.arguments = ["30"]
        try liveProcess.run()
        defer {
            liveProcess.terminate()
            liveProcess.waitUntilExit()
        }

        let owned = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try String(liveProcess.processIdentifier).write(
            to: owned.appendingPathComponent(SandboxFactory.ownerPidFileName),
            atomically: true,
            encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(FileManager.default.fileExists(atPath: owned.path))
    }

    @Test("Given xmr directory owned by a dead process, when removeOrphaned called, then it is removed")
    func removeOrphanedDeletesDeadOwnerDirectory() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let deadProcess = Process()
        deadProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        deadProcess.arguments = ["0"]
        try deadProcess.run()
        deadProcess.waitUntilExit()
        let deadPid = deadProcess.processIdentifier

        let owned = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try String(deadPid).write(
            to: owned.appendingPathComponent(SandboxFactory.ownerPidFileName),
            atomically: true,
            encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: owned.path))
    }

    @Test(
        "Given xmr directory with a nonpositive owner-pid value, when removeOrphaned called, then it is removed",
        arguments: ["0", "-1"]
    )
    func removeOrphanedDeletesDirectoryWithNonpositiveOwnerPid(pidValue: String) throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let owned = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try pidValue.write(
            to: owned.appendingPathComponent(SandboxFactory.ownerPidFileName),
            atomically: true,
            encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: owned.path))
    }

    @Test("Given no active sandbox, when deregister called, then no error occurs")
    func deregisterWithoutRegisterIsNoOp() {
        SandboxCleaner.deregister()
    }

    @Test("Given registered sandbox, when cleanupActiveSandboxes called, then sandbox directory is removed")
    func cleanupActiveSandboxesRemovesRegisteredDirectory() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        let sandboxDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try "content".write(
            to: sandboxDir.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        let sandbox = Sandbox(rootURL: sandboxDir)
        SandboxCleaner.register(sandbox)
        SandboxCleaner.cleanupActiveSandboxes()

        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
        FileHelpers.cleanup(baseDir)
    }

    @Test("Given no registered sandbox, when cleanupActiveSandboxes called, then no error occurs")
    func cleanupActiveSandboxesWithoutRegistrationIsNoOp() {
        SandboxCleaner.deregister()
        SandboxCleaner.cleanupActiveSandboxes()
    }

    @Test("Given registered sandbox, when deregister called, then cleanupActiveSandboxes does not remove directory")
    func deregisterPreventsCleanup() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)

        let sandbox = Sandbox(rootURL: sandboxDir)
        SandboxCleaner.register(sandbox)
        SandboxCleaner.deregister()
        SandboxCleaner.cleanupActiveSandboxes()

        #expect(FileManager.default.fileExists(atPath: sandboxDir.path))
    }

    @Test("Given several registered sandboxes, when cleanupActiveSandboxes called, then all of them are removed")
    func everyRegisteredSandboxIsCleanedUp() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let first = baseDir.appendingPathComponent("xmr-first")
        let second = baseDir.appendingPathComponent("xmr-second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        SandboxCleaner.register(Sandbox(rootURL: first))
        SandboxCleaner.register(Sandbox(rootURL: second))
        SandboxCleaner.cleanupActiveSandboxes()

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test(
        "Given registered sandbox, when the installed handler fires, then sandbox is removed and exit handler called with 1",
        arguments: [SIGINT, SIGTERM]
    )
    func installedHandlerCleansSandboxAndExits(signalNumber: Int32) throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-signal-\(signalNumber)")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try "content".write(
            to: sandboxDir.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.register(Sandbox(rootURL: sandboxDir))
        defer { SandboxCleaner.deregister() }

        let previousExit = sandboxCleanerExitHandler
        resetRecordedExitCodes()
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        installedHandler(for: signalNumber)(signalNumber)

        #expect(waitForRecordedExitCodes(count: 1) == [1])
        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
    }

    @Test("Given no registered sandbox, when the installed handler fires, then exit handler is called with 1")
    func installedHandlerWithNoSandboxStillExits() {
        SandboxCleaner.deregister()

        let previousExit = sandboxCleanerExitHandler
        resetRecordedExitCodes()
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        installedHandler(for: SIGINT)(SIGINT)

        #expect(waitForRecordedExitCodes(count: 1) == [1])
    }

    @Test(
        "Given a notification on the pipe, when the watcher drains it, then sandboxes are removed and exit handler called with 1"
    )
    func signalNotificationDrivesCleanupAndExit() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-notified")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        SandboxCleaner.register(Sandbox(rootURL: sandboxDir))
        defer { SandboxCleaner.deregister() }

        let previousExit = sandboxCleanerExitHandler
        resetRecordedExitCodes()
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        let reader = makePrimedNotificationPipe(notifications: 1)
        defer { close(reader) }
        SandboxCleaner.cleanUpOnSignalNotification(from: reader)

        #expect(recordedExitCodes() == [1])
        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
    }

    @Test(
        "Given no notification before the pipe closes, when the watcher drains it, then nothing is cleaned up and no exit is requested"
    )
    func closedNotificationPipeWithoutNotificationDoesNothing() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-unnotified")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        SandboxCleaner.register(Sandbox(rootURL: sandboxDir))
        defer { SandboxCleaner.deregister() }

        let previousExit = sandboxCleanerExitHandler
        resetRecordedExitCodes()
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        let reader = makePrimedNotificationPipe(notifications: 0)
        defer { close(reader) }
        SandboxCleaner.cleanUpOnSignalNotification(from: reader)

        #expect(recordedExitCodes().isEmpty)
        #expect(FileManager.default.fileExists(atPath: sandboxDir.path))
    }

    @Test("Given a second notification, when the watcher drains it, then it is answered too")
    func watcherAnswersEveryNotification() {
        SandboxCleaner.deregister()

        let previousExit = sandboxCleanerExitHandler
        resetRecordedExitCodes()
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        let reader = makePrimedNotificationPipe(notifications: 2)
        defer { close(reader) }
        SandboxCleaner.cleanUpOnSignalNotification(from: reader)

        #expect(recordedExitCodes() == [1, 1])
    }

    /// The handler `installSignalHandlers` put in place, read back from the process disposition
    /// and restored. Calling it is the closest a test can get to the signal arriving without
    /// actually interrupting the test process.
    private func installedHandler(for signalNumber: Int32) -> @convention(c) (Int32) -> Void {
        SandboxCleaner.installSignalHandlers()
        let handler = signal(signalNumber, SIG_DFL)!
        signal(signalNumber, handler)

        return handler
    }
}
