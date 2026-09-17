import Foundation

struct RunnerConfiguration: Sendable {
    static let defaultXcodeTimeout: Double = 120.0
    static let defaultSPMTimeout: Double = 30.0

    /// A build legitimately takes much longer than a single mutant's test run, so reusing the
    /// per-mutant test timeout defaults as a build bound reported every mutant Unviable on any
    /// project whose build took longer than that. 600s comfortably covers realistic clean and
    /// incremental builds while still failing fast on a genuinely hung one, for both project
    /// types — unlike the test timeout, typical build cost has no evidence of a platform split.
    static let defaultBuildTimeout: Double = 600.0

    static let defaultConcurrency: Int = max(1, ProcessInfo.processInfo.processorCount - 1)

    let projectPath: String
    let build: BuildOptions
    let reporting: ReportingOptions
    let filter: FilterOptions

    struct BuildOptions: Sendable {
        var projectType: ProjectType
        var testTarget: String?
        var timeout: Double

        /// Bounds the schematized build, separate from `timeout`'s per-mutant test bound.
        var buildTimeout: Double = RunnerConfiguration.defaultBuildTimeout
        var concurrency: Int
        var noCache: Bool
        var testingFramework: TestingFramework = .swiftTesting

        /// Test files most likely to kill a mutant in a source file, for sources the
        /// `Foo.swift` → `FooTests.swift` convention does not cover.
        var likelyKillerTests: [String: [String]] = [:]
    }

    struct ReportingOptions: Sendable {
        var output: String?
        var htmlOutput: String?
        var sonarOutput: String?
        var quiet: Bool
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String]
        var operators: [String]

        /// `path:start-end` line sets the run is limited to.
        var scopeLines: [String] = []

        /// Git reference whose diff against the working tree limits the run.
        var since: String?

        /// Mutation report of an earlier full run, read to find the mutants a changed test killed.
        var baselineReport: String?
    }
}
