import Testing

@testable import SwiftMutationTesting

@Suite("SourceFileExclusion")
struct SourceFileExclusionTests {
    private let exclusion = SourceFileExclusion()

    @Test("Given a path under a literal Tests directory with a project-named test subdirectory, when excludes, then returns true")
    func excludesNestedProjectTestDirectory() {
        #expect(exclusion.excludes(path: "Tests/AppTests/Login.swift"))
    }

    @Test("Given a bare project-named test directory with no Tests parent, when excludes, then returns true")
    func excludesBareProjectTestDirectory() {
        #expect(exclusion.excludes(path: "AppTests/Login.swift"))
    }

    @Test("Given a literal Tests directory nested under Sources, when excludes, then returns true")
    func excludesLiteralTestsDirectoryEvenUnderSources() {
        #expect(exclusion.excludes(path: "Sources/Tests/Foo.swift"))
    }

    @Test("Given a source feature directory ending in Tests directly under Sources, when excludes, then returns false")
    func doesNotExcludeSourceFeatureDirectory() {
        #expect(!exclusion.excludes(path: "Sources/ABTests/Foo.swift"))
    }

    @Test("Given a source feature directory ending in Tests nested two levels under Sources, when excludes, then returns false")
    func doesNotExcludeNestedSourceFeatureDirectory() {
        #expect(!exclusion.excludes(path: "Sources/Analytics/ExperimentTests/Foo.swift"))
    }
}
