struct TestExecutionContext: Sendable {
    let artifact: BuildArtifact
    let sandboxes: [Sandbox]
    let pool: SimulatorPool
    let configuration: RunnerConfiguration

    /// Sandbox a worker slot runs its mutants in. One sandbox per worker keeps concurrent
    /// mutants out of each other's build directory; slots wrap when a caller supplies fewer
    /// sandboxes than workers, as the per-file fallback path does with its single sandbox.
    func sandbox(forWorker worker: Int) -> Sandbox {
        sandboxes[worker % sandboxes.count]
    }
}
