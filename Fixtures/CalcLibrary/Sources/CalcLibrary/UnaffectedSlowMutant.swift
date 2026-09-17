import Foundation

/// Named to sort (by file path) immediately after TimeoutTarget.swift, so under
/// --concurrency 1 its mutants are scheduled right after TimeoutTarget's timeout mutant.
struct UnaffectedSlowMutant {
    /// Mutating `<` to `>` makes the tested input take a real, finite 8-second delay before
    /// returning the same value as the original -- a genuine (non-timeout) Survived verdict
    /// that takes long enough to still be running 5 seconds after the preceding mutant's
    /// timeout kill. Used by the timeout-shape test's revert-fail-restore proof to detect
    /// whether the escaped-child cleanup sweep for a timed-out mutant collaterally kills this
    /// one -- it should stay Survived, never poisoned into Crash/Timeout.
    func maybeDelay(_ n: Int) -> Int {
        if n < 0 {
            Thread.sleep(forTimeInterval: 8)
        }
        return n
    }
}
