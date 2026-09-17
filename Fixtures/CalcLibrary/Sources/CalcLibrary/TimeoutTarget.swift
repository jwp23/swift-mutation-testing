import Foundation

struct TimeoutTarget {
    /// Mutating `<` to `>` flips the guard so every input the tests use takes the 60-second
    /// sleep path, parking the test process and forcing the tool's per-mutant timeout. Mutating
    /// `<` to `<=` leaves both tested inputs on the instant path, so that mutant survives.
    /// Used by the timeout-shape test to plant a known timeout mutant alongside real mutants
    /// elsewhere in the fixture, proving a timeout doesn't poison any other mutant's verdict.
    func maybeStall(_ n: Int) -> Int {
        if n < 0 {
            Thread.sleep(forTimeInterval: 60)
        }
        return n
    }
}
