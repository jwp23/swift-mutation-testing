import Testing

@testable import SwiftMutationTesting

@Suite("LikelyKillerTestMapping")
struct LikelyKillerTestMappingTests {
    @Test("Given a source file, when asked for its conventional test file, then it is named after the source")
    func conventionalTestFileIsNamedAfterTheSource() {
        let mapping = LikelyKillerTestMapping(overrides: [:])

        #expect(mapping.conventionalTestFileName(forSourceFile: "/p/Sources/Foo.swift") == "FooTests.swift")
    }

    @Test("Given an override naming the source, when asked, then the configured test files come back")
    func overrideNamesItsTestFiles() {
        let mapping = LikelyKillerTestMapping(overrides: ["Minutes.swift": ["CountdownTests.swift"]])

        #expect(
            mapping.overriddenTestFileNames(forSourceFile: "/p/Sources/Minutes.swift") == ["CountdownTests.swift"]
        )
    }

    @Test("Given two overrides matching the source, when asked, then the more specific key wins")
    func mostSpecificOverrideKeyWins() {
        let mapping = LikelyKillerTestMapping(
            overrides: [
                "Minutes.swift": ["GeneralTests"],
                "App/Core/Minutes.swift": ["CoreMinutesTests"],
            ]
        )

        #expect(
            mapping.overriddenTestFileNames(forSourceFile: "/p/App/Core/Minutes.swift") == ["CoreMinutesTests"]
        )
    }

    @Test("Given no override for the source, when asked, then there is none")
    func sourceWithoutOverrideHasNone() {
        let mapping = LikelyKillerTestMapping(overrides: ["Minutes.swift": ["CountdownTests"]])

        #expect(mapping.overriddenTestFileNames(forSourceFile: "/p/Sources/Foo.swift") == nil)
    }

    @Test("Given a conventionally named test file, when read backwards, then it names its source file")
    func conventionalTestFileNamesItsSource() {
        let mapping = LikelyKillerTestMapping(overrides: [:])

        #expect(mapping.sourceFilePaths(forTestFile: "/p/Tests/FooTests.swift") == ["Foo.swift"])
    }

    @Test("Given a test file listed in an override, when read backwards, then it names the overridden source")
    func overriddenTestFileNamesItsSource() {
        let mapping = LikelyKillerTestMapping(overrides: ["App/Minutes.swift": ["PhaseDisplayTests.swift"]])

        #expect(
            mapping.sourceFilePaths(forTestFile: "/p/Tests/PhaseDisplayTests.swift").sorted()
                == ["App/Minutes.swift", "PhaseDisplay.swift"]
        )
    }

    @Test("Given an override listing a test class rather than a file, when read backwards, then it still matches")
    func overrideListedAsClassNameNamesItsSource() {
        let mapping = LikelyKillerTestMapping(overrides: ["App/Minutes.swift": ["CountdownTests"]])

        #expect(mapping.sourceFilePaths(forTestFile: "/p/Tests/CountdownTests.swift").contains("App/Minutes.swift"))
    }

    @Test("Given a file the convention does not name as a test, when read backwards, then it names no source")
    func unconventionalFileNamesNoSource() {
        let mapping = LikelyKillerTestMapping(overrides: [:])

        #expect(mapping.sourceFilePaths(forTestFile: "/p/Tests/Helpers/Builders.swift").isEmpty)
    }

    @Test("Given a file named only Tests.swift, when read backwards, then it names no source")
    func bareTestsFileNamesNoSource() {
        let mapping = LikelyKillerTestMapping(overrides: [:])

        #expect(mapping.sourceFilePaths(forTestFile: "/p/Tests/Tests.swift").isEmpty)
    }
}
