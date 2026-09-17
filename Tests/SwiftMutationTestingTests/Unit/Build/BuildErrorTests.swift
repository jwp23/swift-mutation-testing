import Testing

@testable import SwiftMutationTesting

@Suite("BuildError")
struct BuildErrorTests {
    @Test("Given compilationFailed with output, when errorDescription accessed, then includes output and message")
    func compilationFailedWithOutput() {
        let error = BuildError.compilationFailed(output: "error: missing semicolon")
        #expect(error.errorDescription?.contains("missing semicolon") == true)
        #expect(error.errorDescription?.contains("Build failed") == true)
    }

    @Test(
        "Given compilationFailed with empty output, when errorDescription accessed, then returns build failed message")
    func compilationFailedEmptyOutput() {
        let error = BuildError.compilationFailed(output: "")
        #expect(error.errorDescription == "Build failed. The schematized source could not be compiled.")
    }

    @Test("Given xctestrunNotFound, when errorDescription accessed, then returns expected message")
    func xctestrunNotFound() {
        let error = BuildError.xctestrunNotFound
        #expect(error.errorDescription == "xctestrun file not found after build.")
    }

    @Test("Given testBundleNotFound, when errorDescription accessed, then returns expected message")
    func testBundleNotFound() {
        let error = BuildError.testBundleNotFound
        #expect(error.errorDescription == "No .xctest bundle found after build.")
    }

    @Test(
        "Given testTargetUnscopable, when errorDescription accessed, then names the target and explains the merged-bundle cause"
    )
    func testTargetUnscopable() {
        let error = BuildError.testTargetUnscopable(testTarget: "MyPackagePackageTests")
        #expect(error.errorDescription?.contains("MyPackagePackageTests") == true)
        #expect(error.errorDescription?.contains("--target") == true)
        #expect(error.errorDescription?.contains("merge all test targets") == true)
    }

    @Test("Given two testTargetUnscopable errors with different targets, when compared, then they are equal")
    func testTargetUnscopableEqualityIgnoresTarget() {
        let lhs = BuildError.testTargetUnscopable(testTarget: "A")
        let rhs = BuildError.testTargetUnscopable(testTarget: "B")
        #expect(lhs == rhs)
    }

    @Test("Given testBundleNotFound and xctestrunNotFound, when compared, then they are not equal")
    func testBundleNotFoundIsNotXctestrunNotFound() {
        #expect(BuildError.testBundleNotFound != BuildError.xctestrunNotFound)
        #expect(BuildError.testBundleNotFound == BuildError.testBundleNotFound)
    }

    @Test("Given two compilationFailed errors, when compared, then they are equal")
    func compilationFailedEquality() {
        let lhs = BuildError.compilationFailed(output: "a")
        let rhs = BuildError.compilationFailed(output: "b")
        #expect(lhs == rhs)
    }

    @Test("Given compilationFailed and xctestrunNotFound, when compared, then they are not equal")
    func differentCasesNotEqual() {
        let lhs = BuildError.compilationFailed(output: "a")
        let rhs = BuildError.xctestrunNotFound
        #expect(lhs != rhs)
    }
}
