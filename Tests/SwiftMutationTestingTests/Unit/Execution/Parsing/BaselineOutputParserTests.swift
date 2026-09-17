import Testing

@testable import SwiftMutationTesting

@Suite("BaselineOutputParser")
struct BaselineOutputParserTests {
    private let parser = BaselineOutputParser()

    /// Verbatim from `xcrun xctest .build/debug/CalcLibraryTests.xctest` over the repository's
    /// own SPM fixture, so the shapes parsed here are the shapes a real baseline run produces.
    private let passingOutput = """
        Test Suite 'All tests' started at 2026-09-17 02:05:40.810.
        Test Suite 'CalcLibraryTests.xctest' started at 2026-09-17 02:05:40.811.
        Test Suite 'CalcLibraryTests' started at 2026-09-17 02:05:40.811.
        Test Case '-[CalcLibraryTests.CalcLibraryTests testAdd]' started.
        Test Case '-[CalcLibraryTests.CalcLibraryTests testAdd]' passed (0.250 seconds).
        Test Case '-[CalcLibraryTests.CalcLibraryTests testSubtract]' started.
        Test Case '-[CalcLibraryTests.CalcLibraryTests testSubtract]' passed (0.125 seconds).
        Test Suite 'CalcLibraryTests' passed at 2026-09-17 02:05:40.812.
        \t Executed 2 tests, with 0 failures (0 unexpected) in 0.375 (0.375) seconds
        """

    @Test("Given a passing run, when parsed, then every test's duration is keyed by class and method")
    func passingRunYieldsPerTestDurations() {
        let result = parser.parse(passingOutput)

        #expect(result.testDurations == ["CalcLibraryTests/testAdd": 0.250, "CalcLibraryTests/testSubtract": 0.125])
        #expect(result.failingTests.isEmpty)
    }

    @Test("Given a failing test, when parsed, then its duration is measured and the test is reported failing")
    func failingTestIsReportedAndStillMeasured() {
        let output = """
            Test Case '-[MyLibTests.FooTests testBar]' started.
            Test Case '-[MyLibTests.FooTests testBar]' failed (0.500 seconds).
            """

        let result = parser.parse(output)

        #expect(result.failingTests == ["MyLibTests.FooTests.testBar"])
        #expect(result.testDurations == ["FooTests/testBar": 0.500])
    }

    @Test("Given several failing tests, when parsed, then all of them are reported once each")
    func everyFailingTestIsReportedOnce() {
        let output = """
            Test Case '-[MyLibTests.FooTests testBar]' failed (0.001 seconds).
            Test Case '-[MyLibTests.FooTests testBar]' failed (0.001 seconds).
            Test Case '-[MyLibTests.FooTests testBaz]' failed (0.002 seconds).
            """

        #expect(parser.parse(output).failingTests == ["MyLibTests.FooTests.testBar", "MyLibTests.FooTests.testBaz"])
    }

    @Test("Given a Swift Testing failure, when parsed, then the failing test is reported")
    func swiftTestingFailureIsReported() {
        let output = #"✘ Test "adds up" failed after 0.003 seconds."#

        #expect(parser.parse(output).failingTests == ["adds up"])
    }

    @Test(
        "Given the same Class/method reported by more than one bundle, when parsed, then its durations are added together"
    )
    func sameTestFromMultipleBundlesAccumulatesItsDuration() {
        let output = """
            Test Case '-[FirstBundleTests.FooTests testBar]' passed (0.300 seconds).
            Test Case '-[SecondBundleTests.FooTests testBar]' passed (0.700 seconds).
            """

        #expect(parser.parse(output).testDurations == ["FooTests/testBar": 1.000])
    }

    @Test("Given output with no test records, when parsed, then nothing is measured and nothing failed")
    func outputWithoutTestRecordsMeasuresNothing() {
        let result = parser.parse("dyld: Library not loaded")

        #expect(result.testDurations.isEmpty)
        #expect(result.failingTests.isEmpty)
    }
}
