/// Whether a Swift file belongs to a project's tests rather than its mutable source: the tests
/// themselves and the doubles that support them, recognised from the path alone.
///
/// The single answer to that question. Discovery skips these files so they carry no mutants
/// (`SourceFileExclusion`), and cache invalidation hashes exactly the same set to tell a changed
/// test from a changed source (`TestFilesHasher`) — two heuristics would eventually disagree and
/// leave a file hashed as a test while it still carried mutants, or the reverse.
///
/// `declaresTests(path:)` asks the narrower question the killer-test bookkeeping needs — which of
/// those files can hold a test at all, as opposed to serving one.
///
/// Build output is deliberately not this type's concern: skipping `.build/` or derived data is
/// about where discovery may walk, not about what a test file is.
enum TestFileConvention {

    /// Filename suffixes and path fragments that name a file which declares tests of its own —
    /// `LoginTests.swift`, a Quick-style `LoginSpec.swift`.
    private static let testCasePatterns: [String] = [
        "Tests.swift",
        "Spec.swift",
    ]

    /// Filename suffixes and path fragments that name a double or shared helper: code written for
    /// the tests that declares none itself.
    private static let testDoublePatterns: [String] = [
        "/Mocks/",
        "/Stubs/",
        "/Fakes/",
        "/TestHelpers/",
        "/TestSupport/",
        "Mock.swift",
    ]

    static func isTestFile(path: String) -> Bool {
        isInTestDirectory(path)
            || matches(path, testCasePatterns)
            || matches(path, testDoublePatterns)
    }

    /// Whether the file can hold a test of its own, and so be named as the test that killed a
    /// mutant. A double or a shared helper declares none: naming one as a killer on a coincidental
    /// text match would leave the cache watching a file that can never change the verdict, while
    /// an edit to the test that really did the killing went unnoticed.
    static func declaresTests(path: String) -> Bool {
        isTestFile(path: path) && !matches(path, testDoublePatterns)
    }

    /// A `.swift` pattern matches the end of the path; anything else matches anywhere in it.
    private static func matches(_ path: String, _ patterns: [String]) -> Bool {
        patterns.contains { pattern in
            pattern.hasSuffix(".swift") ? path.hasSuffix(pattern) : path.contains(pattern)
        }
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
    private static func isInTestDirectory(_ path: String) -> Bool {
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
