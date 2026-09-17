struct TestLaunchResult: Sendable {
    let exitCode: Int32
    let output: String
    let xcresultPath: String
    let duration: Double

    /// Whether the launcher stopped the run as soon as a test failed, leaving the rest of the suite
    /// unrun. The exit code of such a run is the signal that stopped it, so the verdict has to come
    /// from the output instead.
    let stoppedAtFirstFailure: Bool
}
