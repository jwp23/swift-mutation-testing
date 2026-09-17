import Foundation

struct RunnerConfiguration: Sendable {
    static let defaultXcodeTimeout: Double = 120.0
    static let defaultSPMTimeout: Double = 30.0
    static let defaultConcurrency: Int = max(1, ProcessInfo.processInfo.processorCount - 1)

    let projectPath: String
    let build: BuildOptions
    let reporting: ReportingOptions
    let filter: FilterOptions

    struct BuildOptions: Sendable {
        var projectType: ProjectType
        var testTarget: String?
        var timeout: Double
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
