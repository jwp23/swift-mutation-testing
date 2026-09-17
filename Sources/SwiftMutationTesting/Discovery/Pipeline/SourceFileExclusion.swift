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
    private func isInTestDirectory(_ path: String) -> Bool {
        path.split(separator: "/").dropLast().contains { $0.hasSuffix("Tests") }
    }
}
