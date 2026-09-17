struct SPMResultParser: Sendable {
    /// Exit code `ProcessRunner` reports for a process it killed when the timeout expired.
    static let timeoutExitCode: Int32 = -1

    func parse(exitCode: Int32, output: String) -> TestRunOutcome {
        if exitCode == Self.timeoutExitCode { return .timedOut }
        if exitCode == 0 { return .testsSucceeded }

        switch TestOutputParser().parse(output) {
        case .killed(let name): return .testsFailed(failingTest: name)
        case .crashed: return .crashed
        case .unviable: return output.isEmpty ? .crashed : .unviable
        }
    }
}
