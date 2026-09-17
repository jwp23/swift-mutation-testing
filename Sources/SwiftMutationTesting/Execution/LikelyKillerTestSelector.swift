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
        self.mapping = LikelyKillerTestMapping(overrides: overrides)
    }

    /// Which test files the convention and the configured overrides pair with a source file.
    private let mapping: LikelyKillerTestMapping

    /// File names of the project's test files that an XCTest selection can reach, read once when
    /// the selector is built rather than per mutant.
    private let xctestFileNames: Set<String>

    private static func declaresXCTestClass(_ testFilePath: String) -> Bool {
        guard let content = try? String(contentsOfFile: testFilePath, encoding: .utf8) else { return false }

        return content.contains("XCTestCase")
    }

    /// XCTest selection naming the likely killers of a mutant in `sourceFilePath`, or `nil` when
    /// the source has none and only the whole suite can judge it.
    ///
    /// Configured entries are taken at their word — a name that matches nothing simply runs no
    /// tests, and the whole suite still decides survival.
    func selection(forSourceFile sourceFilePath: String) -> String? {
        let testFileNames =
            mapping.overriddenTestFileNames(forSourceFile: sourceFilePath)
            ?? reachableConventionalTestFileNames(for: sourceFilePath)

        guard !testFileNames.isEmpty else { return nil }

        return testFileNames.map(testClassName).joined(separator: ",")
    }

    private func reachableConventionalTestFileNames(for sourceFilePath: String) -> [String] {
        let testFileName = mapping.conventionalTestFileName(forSourceFile: sourceFilePath)

        return xctestFileNames.contains(testFileName) ? [testFileName] : []
    }

    /// The class an XCTest selection names, which a test file declares under its own name.
    private func testClassName(for testFileName: String) -> String {
        URL(fileURLWithPath: testFileName).deletingPathExtension().lastPathComponent
    }
}
