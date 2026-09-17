import Testing

@testable import SwiftMutationTesting

@Suite("SPMResultParser")
struct SPMResultParserTests {
    private let parser = SPMResultParser()

    @Test("Given exit code -1, when parse called, then returns timedOut")
    func exitCodeMinusOneReturnsTimedOut() {
        #expect(parser.parse(exitCode: -1, output: "", stoppedAtFirstFailure: false) == .timedOut)
    }

    @Test("Given exit code 0, when parse called, then returns testsSucceeded")
    func exitCodeZeroReturnsTestsSucceeded() {
        #expect(parser.parse(exitCode: 0, output: "", stoppedAtFirstFailure: false) == .testsSucceeded)
    }

    @Test("Given exit code 1 and Swift Testing failure in output, when parse called, then returns testsFailed")
    func swiftTestingFailureOutputReturnsTestsFailed() {
        let output = #"Test "myTest" failed after 0.001 seconds."#
        let result = parser.parse(exitCode: 1, output: output, stoppedAtFirstFailure: false)
        #expect(result == .testsFailed(failingTest: "myTest"))
    }

    @Test("Given exit code 1 and XCTest failure in output, when parse called, then returns testsFailed")
    func xcTestFailureOutputReturnsTestsFailed() {
        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let result = parser.parse(exitCode: 1, output: output, stoppedAtFirstFailure: false)
        #expect(result == .testsFailed(failingTest: "MySuite.myTest"))
    }

    @Test("Given exit code 1 and crash in output, when parse called, then returns crashed")
    func crashOutputReturnsCrashed() {
        let output = "Test run started.\nFatal error: something went wrong"
        let result = parser.parse(exitCode: 1, output: output, stoppedAtFirstFailure: false)
        #expect(result == .crashed)
    }

    @Test("Given exit code 1 and no recognisable test output, when parse called, then returns unviable")
    func noTestOutputReturnsUnviable() {
        let result = parser.parse(exitCode: 1, output: "something unrelated", stoppedAtFirstFailure: false)
        #expect(result == .unviable)
    }

    @Test("Given a run stopped at its first failing test, when parse called, then returns testsFailed not crashed")
    func stoppedAtFirstFailureReturnsTestsFailed() {
        let output = """
            Test Suite 'MySuite' started at 2026-01-01 00:00:00.000
            Test Case '-[MySuite myTest]' failed (0.002 seconds).
            """
        let result = parser.parse(exitCode: 15, output: output, stoppedAtFirstFailure: true)
        #expect(result == .testsFailed(failingTest: "MySuite.myTest"))
    }

    @Test(
        "Given a run stopped at its first failing test whose exit code reads as a timeout, when parse called, then returns testsFailed"
    )
    func stoppedAtFirstFailureIsNeverATimeout() {
        let output = "Test Case '-[MySuite myTest]' failed (0.002 seconds)."
        let result = parser.parse(exitCode: -1, output: output, stoppedAtFirstFailure: true)
        #expect(result == .testsFailed(failingTest: "MySuite.myTest"))
    }
}
