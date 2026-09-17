import Foundation

/// The pairing between a source file and the test files most likely to kill its mutants: the
/// `Foo.swift` → `FooTests.swift` naming convention, and the configured overrides that replace the
/// convention for sources it does not cover.
///
/// Read forwards to choose the tests to run against a mutant, and backwards to decide which sources
/// a changed test file puts in scope. Backwards, a source is offered whenever either rule pairs it
/// with the test, because a scope that misses a source lets a weakened test pass unexamined while
/// one that includes a source too many only runs mutants that would have run anyway.
struct LikelyKillerTestMapping: Sendable {
    private static let testNameSuffix = "Tests"
    private static let testFileSuffix = "Tests.swift"

    /// Test files listed in the configuration for sources the naming convention does not cover,
    /// keyed by source path suffix.
    let overrides: [String: [String]]

    /// Name of the test file the convention pairs with a source file, whether or not the project
    /// contains such a file.
    func conventionalTestFileName(forSourceFile sourceFilePath: String) -> String {
        let sourceName = URL(fileURLWithPath: sourceFilePath).deletingPathExtension().lastPathComponent

        return "\(sourceName)\(Self.testFileSuffix)"
    }

    /// The configured entry whose key is the longest suffix of the source path, so that an override
    /// naming a directory beats one naming only a file name.
    func overriddenTestFileNames(forSourceFile sourceFilePath: String) -> [String]? {
        overrides
            .filter { sourceFilePath == $0.key || sourceFilePath.hasSuffix("/\($0.key)") }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    /// Paths of the source files a test file is the likely killer for. The convention gives back a
    /// bare file name, which names that source wherever the project keeps it; an override gives back
    /// its own key. Overrides are matched by file name and by class name, either of which a
    /// configured entry may use.
    func sourceFilePaths(forTestFile testFilePath: String) -> [String] {
        let fileName = URL(fileURLWithPath: testFilePath).lastPathComponent
        let testName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent

        var paths =
            overrides
            .filter { $0.value.contains(fileName) || $0.value.contains(testName) }
            .map(\.key)

        if fileName.hasSuffix(Self.testFileSuffix), fileName != Self.testFileSuffix {
            paths.append("\(testName.dropLast(Self.testNameSuffix.count)).swift")
        }

        return paths
    }
}
