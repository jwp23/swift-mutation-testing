/// The Swift files mutation testing leaves alone: the tests themselves, the doubles that support
/// them, and anything a build produced. Discovery skips them, so they carry no mutants — which also
/// makes this the rule that tells a changed test file from a changed source file.
struct SourceFileExclusion: Sendable {
    init(patterns: [String] = []) {
        self.patterns = patterns
    }

    private static let fixed: [String] = [
        "/Mocks/",
        "/Stubs/",
        "/Fakes/",
        "/TestHelpers/",
        "/TestSupport/",
        "Tests.swift",
        "Mock.swift",
        "Spec.swift",
        "/.build/",
        "/.swift-mutation-testing-derived-data/",
        "/\(CacheStore.directoryName)/",
        "/DerivedData/",
    ]

    /// Patterns the run was configured to exclude on top of the fixed ones, matched anywhere in the
    /// path.
    private let patterns: [String]

    func excludes(path: String) -> Bool {
        if isInTestDirectory(path) { return true }

        for pattern in Self.fixed {
            if pattern.hasSuffix(".swift") {
                if path.hasSuffix(pattern) { return true }
            } else if path.contains(pattern) {
                return true
            }
        }

        return patterns.contains { path.contains($0) }
    }

    /// Whether any directory the path passes through is a test target by convention: named
    /// `Tests`, or a project's own name followed by it, such as `AppTests` or `ProjectTests`.
    /// `/Tests/` alone would miss every project that names its test target after itself.
    ///
    /// A component ending in `Tests` doesn't count if an earlier (closer-to-root) component is
    /// literally `Sources` — that marks a source-code feature directory that happens to end in
    /// "Tests" (`Sources/ABTests/`, `Sources/Analytics/ExperimentTests/`), not a test target. A
    /// component that is exactly `Tests` always counts regardless of a `Sources` ancestor,
    /// though that combination shouldn't arise in practice.
    ///
    /// This is a path-based heuristic with no real target list to check against (this codebase
    /// has no Package.swift/`.testTarget` parser). A project checked out under a directory that
    /// happens to be named `Sources` for unrelated reasons could still be misclassified — an
    /// accepted tradeoff.
    private func isInTestDirectory(_ path: String) -> Bool {
        let components = path.split(separator: "/").dropLast()
        var sawSources = false
        for component in components {
            if component == "Tests" { return true }
            if component == "Sources" {
                sawSources = true
                continue
            }
            if component.hasSuffix("Tests") && !sawSources { return true }
        }
        return false
    }
}
