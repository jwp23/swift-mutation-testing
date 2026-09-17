struct RaceTarget {
    /// Only the true branch is tested, so the `>=` mutant keeps the same output and survives
    /// while the `<` mutant flips it and is killed. Used by the two-run race test to plant a
    /// known survivor/killed pair for RelationalOperatorReplacement.
    func isPositive(_ n: Int) -> Bool { n > 0 }

    /// Every input the tests use flips output under the `!=` mutant, so it is always killed.
    /// Used by the two-run race test to plant a known killed-only mutant.
    func isZero(_ n: Int) -> Bool { n == 0 }

    /// Mutating `+` to `-` sends `i` away from `limit` forever, so this mutant hangs and is
    /// expected to time out. Used by the timeout-shape test to plant a known timeout mutant
    /// alongside real pass/fail verdicts elsewhere in the fixture.
    func countUp(to limit: Int) -> Int {
        var i = 0
        while i < limit {
            i = i + 1
        }
        return i
    }
}
