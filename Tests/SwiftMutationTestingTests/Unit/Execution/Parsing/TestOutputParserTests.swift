import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestOutputParser")
struct TestOutputParserTests {
    @Test("Given XCTest failure line, when parsed, then returns killed with suite.test name")
    func parsesXCTestFailureLine() {
        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "MySuite.myTest")
    }

    @Test("Given Swift Testing failure line with checkmark prefix, when parsed, then returns killed with test name")
    func parsesSwiftTestingFailureLineWithPrefix() {
        let output = "✗ Test \"myTestFunction\" failed"
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "myTestFunction")
    }

    @Test("Given indented Swift Testing failure line from xcodebuild, when parsed, then returns killed with test name")
    func parsesIndentedSwiftTestingFailureLine() {
        let output = "    ✗ Test \"myTestFunction\" failed after 0.001 seconds"
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "myTestFunction")
    }

    @Test("Given Swift Testing failure line without prefix, when parsed, then returns killed with test name")
    func parsesSwiftTestingFailureLineWithoutPrefix() {
        let output = "Test \"myTestFunction\" failed after 0.001 seconds"
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "myTestFunction")
    }

    @Test("Given output with fatal error, when parsed, then returns crashed")
    func parsesFatalErrorAsCrashed() {
        let output = "Fatal error: Unexpectedly found nil while unwrapping an Optional value"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given output with TEST FAILED but no test name, when parsed, then returns crashed")
    func parsesTestFailedWithoutNameAsCrashed() {
        let output = "** TEST FAILED **\nExecuted 0 tests"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given output with Testing started marker, when parsed, then returns crashed")
    func parsesTestingStartedAsCrashed() {
        let output = "Testing started\nsome other output"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given output with Test run started marker, when parsed, then returns crashed")
    func parsesTestRunStartedAsCrashed() {
        let output = "Test run started.\nsome other output"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given empty output, when parsed, then returns unviable")
    func parsesEmptyOutputAsUnviable() {
        let result = TestOutputParser().parse("")

        #expect(result == .unviable)
    }

    @Test("Given SPM swift test output with fatal error, when parsed, then returns crashed")
    func parsesSPMFatalErrorCrash() throws {
        let output = try loadTestFixture("spm_xctest_fatal_error")
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given SPM swift test output with EXC_BAD_INSTRUCTION, when parsed, then returns crashed")
    func parsesSPMEXCBadInstructionCrash() throws {
        let output = try loadTestFixture("spm_xctest_exc_bad_instruction")
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given a single XCTest failure line, when the failing test is read from it, then it names that test")
    func namesTheTestAnXCTestFailureLineReports() {
        let line = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."

        #expect(TestOutputParser().failingTest(in: line) == "MySuite.myTest")
    }

    @Test("Given a single Swift Testing failure line, when the failing test is read from it, then it names that test")
    func namesTheTestASwiftTestingFailureLineReports() {
        let line = "\u{2717} Test \"myTestFunction\" failed after 0.001 seconds"

        #expect(TestOutputParser().failingTest(in: line) == "myTestFunction")
    }

    @Test("Given a line reporting no failure, when the failing test is read from it, then it names nothing")
    func namesNothingForALineReportingNoFailure() {
        let line = "Test Case '-[MySuite myTest]' passed (0.001 seconds)."

        #expect(TestOutputParser().failingTest(in: line) == nil)
    }

    @Test(
        "Given a diagnostic line that only mentions a Swift Testing failure phrase mid-sentence, when the failing test is read from it, then it names nothing"
    )
    func namesNothingForADiagnosticLineMentioningTheFailurePhrase() {
        let line = "note: see log for details — Test \"myTestFunction\" failed is a phrase the app itself prints"

        #expect(TestOutputParser().failingTest(in: line) == nil)
    }

    @Test(
        "Given a Swift Testing failure line for a test with no custom display name, when the failing test is read from it, then it names that test's signature"
    )
    func namesTheTestAnUnquotedSwiftTestingFailureLineReports() {
        let line = "✘ Test plainExpectFailure() failed after 0.001 seconds with 1 issue."

        #expect(TestOutputParser().failingTest(in: line) == "plainExpectFailure()")
    }

    @Test(
        "Given a Swift Testing rollup failure line for a parameterized test, when the failing test is read from it, then it names that test's signature"
    )
    func namesTheParameterizedTestAnUnquotedSwiftTestingRollupLineReports() {
        let line = "✘ Test parameterized(value:) with 3 test cases failed after 0.001 seconds with 3 issues."

        #expect(TestOutputParser().failingTest(in: line) == "parameterized(value:)")
    }

    @Test(
        "Given a Swift Testing per-case issue line for a parameterized test, when the failing test is read from it, then it names nothing"
    )
    func namesNothingForASwiftTestingPerCaseIssueLine() {
        let line =
            "✘ Test parameterized(value:) recorded an issue with 1 argument value → 2 at FixtureTests.swift:32:9: Expectation failed: value == 0"

        #expect(TestOutputParser().failingTest(in: line) == nil)
    }

    @Test(
        "Given a Swift Testing rollup passing line for a parameterized test, when the failing test is read from it, then it names nothing"
    )
    func namesNothingForAPassingSwiftTestingRollupLine() {
        let line = "✔ Test parameterized(value:) with 3 test cases passed after 0.001 seconds."

        #expect(TestOutputParser().failingTest(in: line) == nil)
    }

    @Test("Given the Swift Testing run-level rollup line, when the failing test is read from it, then it names nothing")
    func namesNothingForTheSwiftTestingRunRollupLine() {
        let line = "Test run with 1 test in 1 suite failed after 0.001 seconds with 1 issue."

        #expect(TestOutputParser().failingTest(in: line) == nil)
    }

    @Test(
        "Given real SPM swift test output for a Swift Testing failure with no custom display name, when parsed, then returns killed with that test's signature"
    )
    func parsesSPMUnnamedSwiftTestingFailureAsKilled() throws {
        let output = try loadTestFixture("spm_swift_testing_unnamed_failure")
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "plainExpectFailure()")
    }
}
