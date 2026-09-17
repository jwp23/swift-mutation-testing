/// What the unmutated run's output says about the suite: how long each of its tests took, and
/// which of them failed.
struct BaselineOutputParser: Sendable {
    struct Result: Sendable {
        /// Seconds each test took, keyed `Class/method` — the way an XCTest selection names it.
        let testDurations: [String: Double]

        /// Tests the run reported as failed, in the order it reported them.
        let failingTests: [String]
    }

    func parse(_ output: String) -> Result {
        var testDurations: [String: Double] = [:]
        var failingTests: [String] = []

        for line in output.components(separatedBy: "\n") {
            if let failing = TestOutputParser().failingTest(in: line), !failingTests.contains(failing) {
                failingTests.append(failing)
            }

            if let measured = measuredTest(in: line) {
                testDurations[measured.test, default: 0] += measured.seconds
            }
        }

        return Result(testDurations: testDurations, failingTests: failingTests)
    }

    /// The test a line records as finished, and how long it took:
    /// `Test Case '-[MyLibTests.FooTests testBar]' passed (0.123 seconds).` records `FooTests` and
    /// `testBar` taking 0.123 s. The module prefix XCTest prints is dropped, since an XCTest
    /// selection names the class alone. A test that failed is recorded too — it took its time
    /// whatever its verdict.
    private func measuredTest(in line: String) -> (test: String, seconds: Double)? {
        guard
            let start = line.range(of: "Test Case '-[")?.upperBound,
            let end = line.range(of: "]' ")?.lowerBound,
            start < end,
            let seconds = measuredSeconds(in: line)
        else { return nil }

        let parts = line[start ..< end].split(separator: " ", maxSplits: 1)

        guard parts.count == 2, let className = parts[0].components(separatedBy: ".").last else { return nil }

        return ("\(className)/\(parts[1])", seconds)
    }

    /// The `(0.123 seconds)` a finished test's line ends with.
    private func measuredSeconds(in line: String) -> Double? {
        guard
            let end = line.range(of: " seconds)")?.lowerBound,
            let start = line[..<end].lastIndex(of: "(")
        else { return nil }

        return Double(line[line.index(after: start) ..< end])
    }
}
