import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("LikelyKillerTestSelector")
struct LikelyKillerTestSelectorTests {
    @Test("Given a conventionally named XCTest file, when selecting for its source, then its class is selected")
    func conventionalXCTestFileIsSelected() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let selector = LikelyKillerTestSelector(
            testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)],
            overrides: [:]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Foo.swift") == "FooTests")
    }

    @Test("Given the source's test file uses Swift Testing, when selecting, then nothing is selected")
    func swiftTestingTestFileSelectsNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let selector = LikelyKillerTestSelector(
            testFilePaths: [try writeSwiftTestingFile(named: "FooTests.swift", in: dir)],
            overrides: [:]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Foo.swift") == nil)
    }

    @Test("Given no test file named for the source, when selecting, then nothing is selected")
    func sourceWithoutConventionalTestFileSelectsNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let selector = LikelyKillerTestSelector(
            testFilePaths: [try writeXCTestFile(named: "BarTests.swift", in: dir)],
            overrides: [:]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Foo.swift") == nil)
    }

    @Test("Given an override for the source, when selecting, then the configured test classes are selected")
    func overrideSelectsConfiguredTestClasses() {
        let selector = LikelyKillerTestSelector(
            testFilePaths: [],
            overrides: ["Minutes.swift": ["PhaseDisplayTests.swift", "CountdownTests"]]
        )

        #expect(
            selector.selection(forSourceFile: "/p/Sources/App/Minutes.swift")
                == "PhaseDisplayTests,CountdownTests"
        )
    }

    @Test("Given an override keyed by a longer path, when two keys match, then the more specific one wins")
    func mostSpecificOverrideKeyWins() {
        let selector = LikelyKillerTestSelector(
            testFilePaths: [],
            overrides: [
                "Minutes.swift": ["GeneralTests"],
                "App/Core/Minutes.swift": ["CoreMinutesTests"],
            ]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Core/Minutes.swift") == "CoreMinutesTests")
    }

    @Test("Given an override for another source, when selecting, then the naming convention still applies")
    func unrelatedOverrideLeavesConventionIntact() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let selector = LikelyKillerTestSelector(
            testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)],
            overrides: ["Minutes.swift": ["CountdownTests"]]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Foo.swift") == "FooTests")
    }

    @Test("Given an override listing no test, when selecting, then nothing is selected")
    func emptyOverrideSelectsNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let selector = LikelyKillerTestSelector(
            testFilePaths: [try writeXCTestFile(named: "FooTests.swift", in: dir)],
            overrides: ["Foo.swift": []]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Foo.swift") == nil)
    }

    @Test("Given a test file that cannot be read, when selecting, then nothing is selected")
    func unreadableTestFileSelectsNothing() {
        let selector = LikelyKillerTestSelector(
            testFilePaths: ["/nonexistent/FooTests.swift"],
            overrides: [:]
        )

        #expect(selector.selection(forSourceFile: "/p/Sources/App/Foo.swift") == nil)
    }
}

private func writeXCTestFile(named fileName: String, in directory: URL) throws -> String {
    let className = (fileName as NSString).deletingPathExtension
    try FileHelpers.write(
        """
        import XCTest

        final class \(className): XCTestCase {
            func testSomething() {}
        }
        """,
        named: fileName,
        in: directory
    )
    return directory.appendingPathComponent(fileName).path
}

private func writeSwiftTestingFile(named fileName: String, in directory: URL) throws -> String {
    let suiteName = (fileName as NSString).deletingPathExtension
    try FileHelpers.write(
        """
        import Testing

        @Suite("\(suiteName)")
        struct \(suiteName) {
            @Test("something") func something() {}
        }
        """,
        named: fileName,
        in: directory
    )
    return directory.appendingPathComponent(fileName).path
}
