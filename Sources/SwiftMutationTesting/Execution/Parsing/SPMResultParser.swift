struct SPMResultParser: Sendable {
    /// Exit code `ProcessRunner` reports for a process it killed when the timeout expired.
    static let timeoutExitCode: Int32 = -1

    /// `stoppedAtFirstFailure` marks a run the launcher terminated as soon as a test reported a
    /// failure. That run died from the signal that stopped it, so its exit code describes the
    /// signal and not the test suite; only the captured output carries the verdict, and the failure
    /// the stop was decided on is always in it.
    func parse(exitCode: Int32, output: String, stoppedAtFirstFailure: Bool) -> TestRunOutcome {
        if !stoppedAtFirstFailure {
            if exitCode == Self.timeoutExitCode { return .timedOut }
            if exitCode == 0 { return .testsSucceeded }
        }

        switch TestOutputParser().parse(output) {
        case .killed(let name): return .testsFailed(failingTest: name)
        case .crashed: return .crashed
        case .unviable: return output.isEmpty ? .crashed : .unviable
        }
    }
}
