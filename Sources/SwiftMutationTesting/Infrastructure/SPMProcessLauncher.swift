import Foundation

struct SPMProcessLauncher: Sendable, RunnerBackedProcessLaunching {
    func makeRunner() -> ProcessRunner {
        ProcessRunner(
            postTerminationCleanup: { pid in
                kill(-pid, SIGKILL)
            },
            killProcessTree: { pid in
                guard pid > 0 else { return }
                // Snapshot descendants while the root is still alive: once it exits and is
                // reaped, the kernel reparents any surviving descendant to launchd (ppid 1),
                // which severs the ancestry chain this walk depends on. The tree is frozen for
                // the walk and left frozen, so nothing in it can fork past the snapshot — not
                // before SIGTERM lands, and not during the grace period that follows.
                let escaped = frozenDescendantPIDs(of: pid)
                kill(-pid, SIGTERM)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    kill(-pid, SIGKILL)
                    killDescendants(escaped)
                }
            }
        )
    }
}

/// A descendant pid plus the start time the kernel recorded for it at snapshot time. Carried
/// forward so a delayed `killDescendants` can confirm, before signaling, that the pid was not
/// reassigned to an unrelated process in the meantime.
struct DescendantSnapshot {
    let pid: Int32
    let startTime: timeval
}

/// The full live process table, read via `sysctl(KERN_PROC_ALL)`. Darwin can return `ENOMEM`
/// when the table grows between the size query and the data query; retried a bounded number of
/// times rather than surfacing an empty snapshot for what is actually a transient race.
private func liveProcessTable() -> [kinfo_proc] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

    for _ in 0 ..< 5 {
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let procSize = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / procSize)
        if sysctl(&mib, 4, &procs, &size, nil, 0) == 0 {
            return Array(procs.prefix(size / procSize))
        }
        guard errno == ENOMEM else { return [] }
    }

    return []
}

/// Transitive descendants of `rootPID`, found by walking each process's parent pid — never by
/// matching sandbox path text in arguments or environment. Must be called while `rootPID` is
/// still alive: once it exits and is reaped, surviving descendants are reparented to launchd
/// and this walk can no longer find them.
func descendantPIDs(of rootPID: Int32) -> [DescendantSnapshot] {
    guard rootPID > 1 else { return [] }

    let procs = liveProcessTable()

    var childrenByParentPID: [Int32: [Int32]] = [:]
    var startTimeByPID: [Int32: timeval] = [:]
    for proc in procs {
        let pid = proc.kp_proc.p_pid
        guard pid > 1 else { continue }
        let parentPID = proc.kp_eproc.e_ppid
        childrenByParentPID[parentPID, default: []].append(pid)
        startTimeByPID[pid] = proc.kp_proc.p_starttime
    }

    var descendants: [DescendantSnapshot] = []
    var frontier = childrenByParentPID[rootPID] ?? []
    while let pid = frontier.popLast() {
        if let startTime = startTimeByPID[pid] {
            descendants.append(DescendantSnapshot(pid: pid, startTime: startTime))
        }
        frontier.append(contentsOf: childrenByParentPID[pid] ?? [])
    }

    return descendants
}

/// How long `frozenDescendantPIDs` waits before walking the process table again, so that a fork
/// the kernel accepted just before the freeze has finished and its child is visible.
///
/// Sized from measurement: the lag between a child's kernel-recorded start time and the first
/// process-table walk that can see it reached 27ms (p99 17ms) on a ten-core machine held at load
/// average 12, against 1.5ms on the same machine idle. 100ms leaves margin above that for a CI
/// runner with fewer cores under a coverage-instrumented test run — a margin, not a measurement of
/// one. The cost is one interval per freeze in the ordinary case, paid on the path that has already
/// decided to kill a mutant and then waits five seconds before `SIGKILL`.
private let forkSettlingInterval: TimeInterval = 0.1

/// Stops `rootPID`'s process group and every descendant of it, then returns the descendants
/// enumerated while the tree is frozen.
///
/// Freezing first is what makes the snapshot trustworthy. Reading the process table does not
/// stop the tree being read, so a running process can fork between the walk and the `SIGTERM`
/// that follows it; a child that then calls `setsid()` is in neither the snapshot nor the
/// root's process group, and nothing would ever reach it. A stopped process cannot fork.
///
/// Descendants that already escaped the root's process group are not reached by stopping that
/// group, so each newly discovered pid is stopped in turn and the walk repeats, pausing between
/// walks, until a walk that follows a pause finds nothing new — bounded, so a pathological fork
/// rate cannot spin here.
///
/// The tree is deliberately left stopped for the caller to terminate: `SIGTERM` still
/// terminates a stopped process that does not handle it, and `SIGKILL` terminates one that
/// does. Resuming it instead would reopen the same hole for the whole grace period, because an
/// escaped descendant is never signalled by the root group's `SIGTERM` and would go on forking
/// children the snapshot does not name.
///
/// The root frozen here is the `xcrun` that launches a mutant's test bundle (see
/// `TestExecutionStage.launchSPM`), not the test binary itself — that binary is one of the
/// descendants. Whether either installs a `SIGTERM` handler is unconfirmed, so the cost of not
/// resuming the tree is unverified in the handler-present case: the run would wait out the full
/// grace period before `SIGKILL` rather than exiting promptly. Bounded either way — a mutant
/// killed here is already decided, whether by its timeout or by its first failing test.
///
/// A fork the kernel has already accepted when `SIGSTOP` lands still completes — ordinary POSIX
/// signals offer no atomic process-group freeze — so the tree can gain one more process after it
/// is stopped. That child joins the group too late for the group's `SIGSTOP` to have reached it, so
/// it is left running, and it is invisible to a process-table walk until the fork that creates it
/// finishes. Walking again immediately therefore proves nothing: the walk has to pause and look
/// again, which is what `forkSettlingInterval` above is for.
///
/// Residual race, accepted: a fork still invisible after `forkSettlingInterval`, or a chain of
/// them longer than the round bound, is still missed. There is no observable event for "this fork
/// has finished", so the pause can only be sized generously, never proven sufficient.
///
/// Residual race, accepted: each `kill(descendant.pid, SIGSTOP)` below signals by bare pid,
/// with no atomic way to bind the signal to the exact process identity (pid plus start time)
/// this walk just recorded for it. If that pid exits and is reused by an unrelated live process
/// in the narrow window between recording its start time and this call, `SIGSTOP` freezes that
/// unrelated process instead. `killDescendants`'s start-time check would then correctly refuse
/// to ever kill or resume it, since its start time won't match the stale snapshot — so a wrongly
/// frozen process would stay stopped indefinitely. macOS has no pidfd-equivalent primitive for
/// signaling an arbitrary discovered pid by identity rather than by number, so there is no clean
/// fix available; the window is extremely narrow (kernel pid allocation plus this function's own
/// negligible per-iteration work), and is accepted as-is rather than engineering new
/// identity-bound signaling infrastructure for it.
func frozenDescendantPIDs(
    of rootPID: Int32,
    walking walk: (Int32) -> [DescendantSnapshot] = descendantPIDs(of:)
) -> [DescendantSnapshot] {
    guard rootPID > 1 else { return [] }

    kill(-rootPID, SIGSTOP)

    var stoppedPIDs: Set<Int32> = []
    var accumulated: [Int32: DescendantSnapshot] = [:]

    for round in 0 ..< 5 {
        // A walk that finds nothing new only means the tree is quiescent if it happened after any
        // fork still in flight had time to become visible; back to back, it merely means the
        // previous walk's process-table read is a few hundred microseconds old.
        if round > 0 { Thread.sleep(forTimeInterval: forkSettlingInterval) }

        // Accumulated by pid rather than replaced each round: a later round's process-table
        // read can legitimately return fewer entries than an earlier one (the retried sysctl in
        // `liveProcessTable()` still exhausts and returns empty on a persistent failure), and a
        // descendant already stopped in an earlier round must still be returned so the delayed
        // `killDescendants` can find and kill it.
        let found = walk(rootPID)
        for descendant in found {
            accumulated[descendant.pid] = descendant
        }

        // The first walk is never conclusive on its own, even when it finds nothing: a root that
        // has just forked its first child is stopped with that child still invisible.
        let newlyFound = found.filter { !stoppedPIDs.contains($0.pid) }
        if newlyFound.isEmpty, round > 0 { break }
        for descendant in newlyFound {
            kill(descendant.pid, SIGSTOP)
            stoppedPIDs.insert(descendant.pid)
        }
    }

    return Array(accumulated.values)
}

/// Kills each snapshot's pid, plus any process group it leads. Each snapshot carries the start
/// time the kernel recorded for its pid when it was discovered; a pid whose current start time no
/// longer matches is skipped rather than signaled, since that pid has been reassigned to an
/// unrelated process in the meantime. Intended for a descendant set captured earlier by
/// `frozenDescendantPIDs(of:)`, since by kill time the original root may already be gone from the
/// process table and, over the delay, the pid could have been reused by an unrelated process.
func killDescendants(_ snapshots: [DescendantSnapshot]) {
    var currentStartTimeByPID: [Int32: timeval] = [:]
    for proc in liveProcessTable() {
        currentStartTimeByPID[proc.kp_proc.p_pid] = proc.kp_proc.p_starttime
    }

    for snapshot in snapshots {
        guard let currentStartTime = currentStartTimeByPID[snapshot.pid],
            currentStartTime.tv_sec == snapshot.startTime.tv_sec,
            currentStartTime.tv_usec == snapshot.startTime.tv_usec
        else { continue }
        kill(-snapshot.pid, SIGKILL)
        kill(snapshot.pid, SIGKILL)
    }
}
