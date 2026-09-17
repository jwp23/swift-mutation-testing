@testable import SwiftMutationTesting

func makeRunnerConfiguration(
    projectPath: String = "/tmp",
    projectType: ProjectType = .xcode(scheme: "MyScheme", destination: "platform=macOS"),
    testTarget: String? = nil,
    testingFramework: TestingFramework = .swiftTesting,
    timeout: Double = 60,
    concurrency: Int = 1,
    noCache: Bool = false,
    output: String? = nil,
    htmlOutput: String? = nil,
    sonarOutput: String? = nil,
    quiet: Bool = true,
    excludePatterns: [String] = [],
    operators: [String] = [],
    scopeLines: [String] = [],
    since: String? = nil,
    baselineReport: String? = nil,
    likelyKillerTests: [String: [String]] = [:]
) -> RunnerConfiguration {
    RunnerConfiguration(
        projectPath: projectPath,
        build: .init(
            projectType: projectType,
            testTarget: testTarget,
            timeout: timeout,
            concurrency: concurrency,
            noCache: noCache,
            testingFramework: testingFramework,
            likelyKillerTests: likelyKillerTests
        ),
        reporting: .init(
            output: output,
            htmlOutput: htmlOutput,
            sonarOutput: sonarOutput,
            quiet: quiet
        ),
        filter: .init(
            excludePatterns: excludePatterns,
            operators: operators,
            scopeLines: scopeLines,
            since: since,
            baselineReport: baselineReport
        )
    )
}
