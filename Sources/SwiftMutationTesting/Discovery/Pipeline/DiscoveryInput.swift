struct DiscoveryInput: Sendable {
    let projectPath: String
    let projectType: ProjectType
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let sourcesPath: String
    let excludePatterns: [String]
    let operators: [String]

    /// The lines this run tests, or nil when it tests every mutant it discovers.
    let scope: MutantScope?
}
