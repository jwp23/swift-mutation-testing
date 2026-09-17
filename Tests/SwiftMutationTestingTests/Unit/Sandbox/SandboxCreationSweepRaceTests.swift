import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Sandbox creation versus orphan sweep")
struct SandboxCreationSweepRaceTests {

    @Test("Given a sandbox mid-creation, when a concurrent sweep runs, then the sandbox survives")
    func sweepDuringCreationPreservesSandbox() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let creationWindowOpen = DispatchSemaphore(value: 0)
        let sweepFinished = DispatchSemaphore(value: 0)

        sandboxRootCreatedHook = {
            creationWindowOpen.signal()
            Thread.sleep(forTimeInterval: 0.2)
        }
        defer { sandboxRootCreatedHook = nil }

        DispatchQueue.global().async {
            creationWindowOpen.wait()
            SandboxCleaner.removeOrphaned(in: baseDir)
            sweepFinished.signal()
        }

        let sandboxURL = try SandboxFactory().makeSandboxRoot(in: baseDir)
        sweepFinished.wait()

        let pidFile = sandboxURL.appendingPathComponent(SandboxFactory.ownerPidFileName)
        #expect(FileManager.default.fileExists(atPath: sandboxURL.path))
        #expect(FileManager.default.fileExists(atPath: pidFile.path))
    }

    @Test(
        "Given the sandbox lock cannot be acquired, when makeSandboxRoot is called, then it throws rather than creating an unlocked sandbox"
    )
    func makeSandboxRootThrowsWhenLockCannotBeAcquired() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        // A directory at the lock file's path makes open(2) fail with EISDIR — a deterministic,
        // permission-free way to force lock acquisition to fail.
        let lockPath = baseDir.appendingPathComponent(SandboxDirectoryLock.fileName)
        try FileManager.default.createDirectory(at: lockPath, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try SandboxFactory().makeSandboxRoot(in: baseDir)
        }
    }

    @Test(
        "Given the sandbox lock cannot be acquired, when removeOrphaned is called, then the sweep is skipped without crashing"
    )
    func removeOrphanedSkipsSweepWhenLockCannotBeAcquired() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let lockPath = baseDir.appendingPathComponent(SandboxDirectoryLock.fileName)
        try FileManager.default.createDirectory(at: lockPath, withIntermediateDirectories: true)

        let orphan = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        SandboxCleaner.removeOrphaned(in: baseDir)

        // The sweep could not acquire the lock, so it must not have touched anything — never
        // silently fall back to sweeping unlocked.
        #expect(FileManager.default.fileExists(atPath: orphan.path))
    }
}
