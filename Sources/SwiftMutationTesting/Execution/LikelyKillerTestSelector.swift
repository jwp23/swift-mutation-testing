import Foundation

/// The tests most likely to kill a mutant in a given source file. `Foo.swift` is covered by
/// `FooTests.swift` unless the configuration maps that source onto other test files; a source
/// whose conventional test file the project does not contain has no likely killers at all, and
/// its mutants go straight to the whole suite.
///
/// The selection it produces is an XCTest one, which selects nothing at all in a Swift Testing
/// suite — so the convention only offers test files that declare an XCTest class, and a package
/// tested entirely with Swift Testing gets no selection and no wasted run.
struct LikelyKillerTestSelector: Sendable {

    init(testFilePaths: [String], overrides: [String: [String]]) {
        self.xctestFileNames = Set(
            testFilePaths
                .filter(Self.declaresXCTestClass)
                .map { URL(fileURLWithPath: $0).lastPathComponent }
        )
        self.overrides = overrides
    }

    /// Test files listed in the configuration for sources the naming convention does not cover,
    /// keyed by source path suffix. Configured entries are taken at their word — a name that
    /// matches nothing simply runs no tests, and the whole suite still decides survival.
    let overrides: [String: [String]]

    /// File names of the project's test files that an XCTest selection can reach, read once when
    /// the selector is built rather than per mutant.
    private let xctestFileNames: Set<String>

    private static func declaresXCTestClass(_ testFilePath: String) -> Bool {
        guard let content = try? String(contentsOfFile: testFilePath, encoding: .utf8) else { return false }

        return content.contains("XCTestCase")
    }

    /// XCTest selection naming the likely killers of a mutant in `sourceFilePath`, or `nil` when
    /// the source has none and only the whole suite can judge it.
    func selection(forSourceFile sourceFilePath: String) -> String? {
        let testFileNames =
            overriddenTestFileNames(for: sourceFilePath)
            ?? conventionalTestFileNames(for: sourceFilePath)

        guard !testFileNames.isEmpty else { return nil }

        return testFileNames.map(testClassName).joined(separator: ",")
    }

    /// The configured entry whose key is the longest suffix of the source path, so that an
    /// override naming a directory beats one naming only a file name.
    private func overriddenTestFileNames(for sourceFilePath: String) -> [String]? {
        overrides
            .filter { sourceFilePath == $0.key || sourceFilePath.hasSuffix("/\($0.key)") }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    private func conventionalTestFileNames(for sourceFilePath: String) -> [String] {
        let sourceName = URL(fileURLWithPath: sourceFilePath).deletingPathExtension().lastPathComponent
        let testFileName = "\(sourceName)Tests.swift"

        return xctestFileNames.contains(testFileName) ? [testFileName] : []
    }

    /// The class an XCTest selection names, which a test file declares under its own name.
    private func testClassName(for testFileName: String) -> String {
        URL(fileURLWithPath: testFileName).deletingPathExtension().lastPathComponent
    }
}
