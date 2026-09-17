import Foundation

/// The scope a run is limited to, gathered from the flags that name it: explicit line sets, the diff
/// since a git reference, and — for the test files either of those names — the sources those tests
/// cover, plus the mutants a baseline report says they used to kill.
///
/// A test file carries no mutants of its own, so a run scoped to a diff alone would pass a
/// test-only change without having tested anything. The test files are expanded here, while the
/// scope is still being built, so that everything downstream sees one line set and one filter.
struct ScopeResolver: Sendable {
    let launcher: any ProcessLaunching

    /// The run's scope, or nil when no flag asked for one and every discovered mutant is tested.
    func resolve(configuration: RunnerConfiguration) async throws -> MutantScope? {
        let filter = configuration.filter
        let isScoped = !filter.scopeLines.isEmpty || filter.since != nil

        guard filter.baselineReport == nil || isScoped else {
            throw UsageError(message: "--baseline-report requires --scope-lines or --since")
        }

        guard isScoped else { return nil }

        var scope = try ScopeLineSpecParser().parse(filter.scopeLines)

        if let ref = filter.since {
            let diff = try await GitDiffReader(launcher: launcher)
                .diff(since: ref, projectPath: configuration.projectPath)
            scope = scope.union(GitDiffParser().parse(diff))
        }

        return scope.union(try testFileScope(in: scope, configuration: configuration))
    }

    /// What the test files a scope names put in scope besides themselves: the sources they cover,
    /// whole, and — where a baseline report is given — every mutant they killed, in whichever file
    /// it lives.
    private func testFileScope(in scope: MutantScope, configuration: RunnerConfiguration) throws -> MutantScope {
        let exclusion = SourceFileExclusion(patterns: configuration.filter.excludePatterns)

        // Classified on the absolute path, which is the form discovery applies the same rules to. A
        // diff names `Tests/AppTests/Login.swift`, and the directory rules — `/Tests/`, `/Mocks/` —
        // only recognise a test file once the path leading to it is whole.
        let testFilePaths =
            scope.paths
            .filter { $0.hasSuffix(".swift") }
            .map { absolutePath(of: $0, in: configuration.projectPath) }
            .filter { exclusion.excludes(path: $0) }

        guard !testFilePaths.isEmpty else { return MutantScope(lineRangesByPath: [:]) }

        let covered = coveredSourceScope(forTestFiles: testFilePaths, configuration: configuration)

        guard let reportPath = configuration.filter.baselineReport else { return covered }

        return covered.union(try BaselineReport(path: reportPath).scope(killedByTestsIn: testFilePaths))
    }

    /// The sources the changed test files are the likely killers for, in scope whole: a test that
    /// changed is judged against every mutant of the source it covers, not only the ones on lines
    /// the same diff happened to touch.
    private func coveredSourceScope(
        forTestFiles testFilePaths: [String],
        configuration: RunnerConfiguration
    ) -> MutantScope {
        let mapping = LikelyKillerTestMapping(overrides: configuration.build.likelyKillerTests)
        let sourcePaths = testFilePaths.flatMap { mapping.sourceFilePaths(forTestFile: $0) }

        return MutantScope(
            lineRangesByPath: Dictionary(
                sourcePaths.map { ($0, [MutantScope.everyLine]) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    /// A diff names a file relative to the project, which is the form the scope keeps. Recognising
    /// the file and reading it both need the path the project actually holds it at.
    private func absolutePath(of path: String, in projectPath: String) -> String {
        path.hasPrefix("/") ? path : URL(fileURLWithPath: projectPath).appendingPathComponent(path).path
    }
}
