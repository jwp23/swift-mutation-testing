import Testing

@testable import SwiftMutationTesting

@Suite("SourceFileExclusion")
struct SourceFileExclusionTests {
    private let exclusion = SourceFileExclusion()

    @Test(
        "Given a path under a literal Tests directory with a project-named test subdirectory, when excludes, then returns true"
    )
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

    @Test(
        "Given a source feature directory ending in Tests nested two levels under Sources, when excludes, then returns false"
    )
    func doesNotExcludeNestedSourceFeatureDirectory() {
        #expect(!exclusion.excludes(path: "Sources/Analytics/ExperimentTests/Foo.swift"))
    }

    @Test("Given a test-double directory outside any test target, when excludes, then returns true")
    func excludesTestDoubleDirectory() {
        #expect(exclusion.excludes(path: "Sources/Support/Mocks/Network.swift"))
    }

    @Test("Given a file named after a test double, when excludes, then returns true")
    func excludesTestDoubleFileName() {
        #expect(exclusion.excludes(path: "Sources/Payments/PaymentGatewayMock.swift"))
    }

    @Test("Given a path inside build output, when excludes, then returns true")
    func excludesBuildOutput() {
        #expect(exclusion.excludes(path: "Sources/.build/checkouts/Package/Foo.swift"))
    }

    @Test("Given a configured exclude pattern matching the path, when excludes, then returns true")
    func excludesConfiguredPattern() {
        #expect(SourceFileExclusion(patterns: ["Generated"]).excludes(path: "Sources/App/GeneratedModel.swift"))
    }

    @Test("Given an ordinary source file, when excludes, then returns false")
    func doesNotExcludeOrdinarySourceFile() {
        #expect(!exclusion.excludes(path: "Sources/App/Login.swift"))
    }
}
