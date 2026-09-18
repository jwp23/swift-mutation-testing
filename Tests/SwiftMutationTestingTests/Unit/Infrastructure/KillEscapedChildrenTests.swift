import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("descendantPIDs and killDescendants")
struct KillEscapedChildrenTests {
    @Test(
        "Given a descendant of a live root pid, when descendantPIDs and killDescendants are used, then the descendant is killed"
    )
    func descendantPIDsFindsAndKillsRealDescendant() async throws {
        let pidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pidFileURL) }

        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/sh")
        parent.arguments = ["-c", "sleep 60 & echo $! > '\(pidFileURL.path)'; wait"]
        parent.standardOutput = FileHandle.nullDevice
        parent.standardError = FileHandle.nullDevice
        try parent.run()
        defer { if parent.isRunning { parent.terminate() } }

        let childPID = try await readPID(from: pidFileURL)
        #expect(kill(childPID, 0) == 0)

        let descendants = descendantPIDs(of: parent.processIdentifier)
        #expect(descendants.contains { $0.pid == childPID })

        killDescendants(descendants)

        try await Task.sleep(for: .milliseconds(300))
        #expect(kill(childPID, 0) == -1)
    }

    @Test(
        "Given a process unrelated to the root pid, when descendantPIDs and killDescendants are used, then the unrelated process is not killed"
    )
    func doesNotKillUnrelatedProcess() async throws {
        // root must have a real descendant: otherwise descendantPIDs(of:) returns an empty
        // snapshot and killDescendants([]) exercises nothing, so the assertion below would pass
        // even if the exclusion logic were broken.
        let root = Process()
        root.executableURL = URL(fileURLWithPath: "/bin/sh")
        root.arguments = ["-c", "sleep 60 & wait"]
        root.standardOutput = FileHandle.nullDevice
        root.standardError = FileHandle.nullDevice
        try root.run()
        defer { if root.isRunning { root.terminate() } }

        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["60"]
        unrelated.standardOutput = FileHandle.nullDevice
        unrelated.standardError = FileHandle.nullDevice
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }

        try await Task.sleep(for: .milliseconds(200))
        #expect(unrelated.isRunning)

        let descendants = descendantPIDs(of: root.processIdentifier)
        #expect(!descendants.isEmpty)
        killDescendants(descendants)

        try await Task.sleep(for: .milliseconds(300))
        #expect(unrelated.isRunning)
    }

    @Test(
        "Given a mutant timeout followed by a second mutant sharing the sandbox, when the escaped-children sweep fires, then the second mutant is not killed",
        .timeLimit(.minutes(1))
    )
    func timedOutMutantDoesNotKillLaterMutantInSameSandbox() async throws {
        // Reproduces throwntom-2dsf/throwntom-ufqt: every mutant of a run shares one sandbox
        // directory, so a naive argv/environment text match against the sandbox path collateral-
        // kills whichever unrelated mutant happens to be in flight five seconds after a timeout.
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxURL) }

        let markerURL = sandboxURL.appendingPathComponent("mutant2-completed")
        let scriptURL = sandboxURL.appendingPathComponent("mutant2.sh")
        try "sleep 6; touch '\(markerURL.path)'".write(to: scriptURL, atomically: true, encoding: .utf8)

        let launcher = SPMProcessLauncher()

        async let mutant1: Int32 = launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            workingDirectoryURL: sandboxURL,
            timeout: 0.3
        )

        // mutant2's own argv contains the sandbox path (its script lives inside the sandbox),
        // exactly like a real mutant's compiled test binary path does.
        async let mutant2: Int32 = launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            workingDirectoryURL: sandboxURL,
            timeout: 10
        )

        let mutant1ExitCode = try await mutant1
        let mutant2ExitCode = try await mutant2

        #expect(mutant1ExitCode == -1)
        #expect(mutant2ExitCode == 0)
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test(
        "Given a mutant whose child escapes the process group via setsid, when the mutant times out, then the escaped descendant is still killed after the grace period",
        .timeLimit(.minutes(1))
    )
    func timeoutKillsEscapedGroupDescendantAfterRootIsReaped() async throws {
        // Matches production ordering: by the time postTerminationCleanup/killDescendants would
        // naively walk the process table, the timed-out root has already exited and been
        // reaped, so any surviving descendant has been reparented to launchd (ppid 1). Only a
        // snapshot taken before SIGTERM (while the root is still alive) can still find and kill
        // a descendant that escaped the process group via setsid.
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxURL) }

        // macOS ships no `setsid` binary; use Perl's POSIX::setsid() to detach the child into
        // its own session/process group, same effect: unreachable by kill(-pid, ...) on the
        // root's original group.
        let pidFileURL = sandboxURL.appendingPathComponent("escaped.pid")
        let scriptURL = sandboxURL.appendingPathComponent("escape.sh")
        try """
        perl -e 'use POSIX "setsid"; setsid(); open(F, ">", "\(pidFileURL.path)") or die; print F "$$\\n"; close F; sleep 60' &
        wait
        """.write(to: scriptURL, atomically: true, encoding: .utf8)

        let launcher = SPMProcessLauncher()
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            workingDirectoryURL: sandboxURL,
            timeout: 0.3
        )
        #expect(exitCode == -1)

        let escapedPID = try await readPID(from: pidFileURL)

        // Still alive immediately after timeout: it escaped the process group, so the initial
        // kill(-pid, SIGTERM)/kill(-pid, SIGKILL) on the root's own group never reached it.
        #expect(kill(escapedPID, 0) == 0)

        // After the grace period, the pre-SIGTERM snapshot's follow-up kill must have reached it.
        try await Task.sleep(for: .seconds(5.5))
        #expect(kill(escapedPID, 0) == -1)
    }

    @Test(
        "Given a root that keeps spawning descendants, when the descendant snapshot is taken, then nothing forked afterwards escapes it",
        .timeLimit(.minutes(1))
    )
    func descendantSnapshotCannotBeOutrunByLaterForks() async throws {
        // Reading the process table does not stop the tree being read, so a root that is still
        // running can fork past the walk that is meant to enumerate it. Anything it forks after
        // the walk is absent from the snapshot, and a child that calls setsid() is absent from
        // the root's process group too, so neither the snapshot's kill nor the group's kill
        // reaches it. The snapshot is only trustworthy if the tree is frozen while it is taken.
        let root = Process()
        root.executableURL = URL(fileURLWithPath: "/bin/sh")
        root.arguments = ["-c", "i=0; while [ $i -lt 40 ]; do sleep 60 & i=$((i+1)); sleep 0.05; done; wait"]
        root.standardOutput = FileHandle.nullDevice
        root.standardError = FileHandle.nullDevice
        try root.run()
        // Precondition the freeze depends on: the launched process leads its own process group,
        // so group-wide signals reach it and everything it spawns.
        #expect(kill(-root.processIdentifier, 0) == 0)
        defer {
            kill(-root.processIdentifier, SIGKILL)
            kill(root.processIdentifier, SIGKILL)
        }

        // Poll for the first fork rather than sleeping a fixed duration: on a loaded CI runner,
        // a fixed wait can elapse before the shell has even been scheduled to run its first
        // loop iteration, taking the snapshot of a still-empty tree. The spawn loop still has
        // dozens of forks ahead of it at this point (cadence ~50ms, 40 total), so the freeze
        // below is still exercised against an actively-forking tree, not a finished one.
        var preSnapshotCount = descendantPIDs(of: root.processIdentifier).count
        for _ in 0 ..< 500 where preSnapshotCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
            preSnapshotCount = descendantPIDs(of: root.processIdentifier).count
        }
        #expect(preSnapshotCount > 0)

        let snapshot = frozenDescendantPIDs(of: root.processIdentifier)
        #expect(!snapshot.isEmpty)

        // Sample repeatedly over a window rather than sleeping once and reading once: a single
        // end-of-window read is itself a fixed-timing assumption about when a leaked fork would
        // be visible. Several more forks would land across this window at the root's spawn
        // cadence if the freeze above failed to hold.
        let snapshotPIDs = Set(snapshot.map(\.pid))
        var appearedAfterSnapshot: [DescendantSnapshot] = []
        for _ in 0 ..< 10 {
            try await Task.sleep(for: .milliseconds(50))
            appearedAfterSnapshot += descendantPIDs(of: root.processIdentifier)
                .filter { !snapshotPIDs.contains($0.pid) }
        }
        #expect(appearedAfterSnapshot.isEmpty)
    }

    @Test(
        "Given an escaped descendant that forks again after the snapshot, when the mutant times out, then no descendant of the timed-out root survives",
        .timeLimit(.minutes(1))
    )
    func timeoutLeavesNoSurvivorWhenAnEscapedDescendantForksAfterTheSnapshot() async throws {
        // A descendant that escaped the root's process group is untouched by the timeout's
        // SIGTERM, so it keeps running for the whole grace period and can fork a child of its
        // own long after the snapshot was taken. That grandchild is in neither the snapshot nor
        // any process group the sweep signals, so it outlives the run entirely unless the whole
        // descendant tree is frozen at snapshot time and left frozen until it is killed.
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxURL) }

        let escapedPIDFileURL = sandboxURL.appendingPathComponent("escaped.pid")
        let grandchildPIDFileURL = sandboxURL.appendingPathComponent("grandchild.pid")
        let scriptURL = sandboxURL.appendingPathComponent("escape-then-fork.sh")
        try """
        perl -e 'use POSIX "setsid";
          setsid();
          open(F, ">", "\(escapedPIDFileURL.path)") or die; print F "$$\\n"; close F;
          sleep 2;
          my $child = fork();
          if (!$child) {
            setsid();
            open(G, ">", "\(grandchildPIDFileURL.path)") or die; print G "$$\\n"; close G;
            sleep 60;
            exit 0;
          }
          sleep 60' &
        wait
        """.write(to: scriptURL, atomically: true, encoding: .utf8)

        let launcher = SPMProcessLauncher()
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            workingDirectoryURL: sandboxURL,
            timeout: 1
        )
        #expect(exitCode == -1)

        // Proves the setup: the descendant escaped the process group before the timeout fired.
        let escapedPID = try await readPID(from: escapedPIDFileURL)

        // Past the launcher's five-second grace period, and past the escaped descendant's own
        // fork, which it attempts one second after the timeout.
        try await Task.sleep(for: .seconds(5.5))

        let grandchildPID = (try? String(contentsOf: grandchildPIDFileURL, encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let survivors = ([escapedPID] + [grandchildPID].compactMap { $0 })
            .filter { kill($0, 0) == 0 }
        for pid in survivors {
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }

        #expect(survivors.isEmpty, "descendants of the timed-out root survived: \(survivors)")
    }

    @Test(
        "Given a snapshot whose recorded start time no longer matches the live process, when killDescendants is used, then the live process is not killed"
    )
    func doesNotKillProcessWhoseStartTimeNoLongerMatches() async throws {
        // Simulates PID reuse during the 5-second delay: the snapshot's pid is correct but its
        // recorded start time is stale, exactly as it would be if the original descendant had
        // exited and the kernel reassigned its pid to this unrelated live process.
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["60"]
        unrelated.standardOutput = FileHandle.nullDevice
        unrelated.standardError = FileHandle.nullDevice
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }

        try await Task.sleep(for: .milliseconds(200))

        let staleStartTime = timeval(tv_sec: 1, tv_usec: 0)
        let staleSnapshot = DescendantSnapshot(pid: unrelated.processIdentifier, startTime: staleStartTime)

        killDescendants([staleSnapshot])

        try await Task.sleep(for: .milliseconds(300))
        #expect(unrelated.isRunning)
    }

    @Test(
        "Given a later discovery round returns fewer descendants than an earlier round, when frozenDescendantPIDs walks, then the earlier round's descendants are still returned"
    )
    func frozenDescendantPIDsAccumulatesAcrossRounds() {
        // Fake pids chosen above Darwin's PID_MAX (99999), so the real kill(2) calls this
        // exercises are always ESRCH against them — never able to collide with, let alone
        // signal, an actual process on the machine running this test.
        let first = DescendantSnapshot(pid: 500_001, startTime: timeval(tv_sec: 1, tv_usec: 0))
        let second = DescendantSnapshot(pid: 500_002, startTime: timeval(tv_sec: 2, tv_usec: 0))
        let rounds: [[DescendantSnapshot]] = [[first], [first, second], []]
        var roundIndex = 0

        let result = frozenDescendantPIDs(of: 500_000) { _ in
            defer { roundIndex += 1 }
            return roundIndex < rounds.count ? rounds[roundIndex] : []
        }

        #expect(Set(result.map(\.pid)) == [500_001, 500_002])
    }

    private func readPID(from url: URL, timeout: TimeInterval = 2) async throws -> Int32 {
        // Poll until the content parses, not until the file exists: each writer (shell
        // redirection, or Perl's open(">") followed by a separate print) makes the path visible
        // before the pid bytes land in it, so an existence check alone can read empty or
        // partial content.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let pid = Int32(contents)
            {
                return pid
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try #require(Int32(contents))
    }
}
