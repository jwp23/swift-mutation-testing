/// The Swift files mutation testing leaves alone: the tests themselves, the doubles that support
/// them (both per `TestFileConvention`), and anything a build produced. Discovery skips them, so
/// they carry no mutants — which also makes this the rule that tells a changed test file from a
/// changed source file.
struct SourceFileExclusion: Sendable {
    init(patterns: [String] = []) {
        self.patterns = patterns
    }

    /// Directories a build or a previous run wrote into, which hold no source of the project's
    /// own. Unlike the test-file rules this is purely about where discovery may walk.
    private static let buildOutputDirectories: [String] = [
        "/.build/",
        "/\(CacheStore.directoryName)/",
        "/DerivedData/",
    ]

    /// Patterns the run was configured to exclude on top of the fixed ones, matched anywhere in the
    /// path.
    private let patterns: [String]

    func excludes(path: String) -> Bool {
        if TestFileConvention.isTestFile(path: path) { return true }
        if Self.buildOutputDirectories.contains(where: { path.contains($0) }) { return true }

        return patterns.contains { path.contains($0) }
    }
}
