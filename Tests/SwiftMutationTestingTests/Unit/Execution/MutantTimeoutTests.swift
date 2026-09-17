import Testing

@testable import SwiftMutationTesting

@Suite("MutantTimeout")
struct MutantTimeoutTests {

    @Test("Given no baseline was measured, when a mutant's timeout is computed, then the configured one stands")
    func withoutABaselineTheConfiguredTimeoutStands() {
        let timeout = MutantTimeout(baseline: nil, configuredTimeout: 30)

        #expect(timeout.seconds(forSelection: nil) == 30)
    }

    @Test("Given a suite slower than the configured timeout, when computed, then the timeout scales with the baseline")
    func slowBaselineScalesTheTimeout() {
        let timeout = MutantTimeout(
            baseline: BaselineMeasurement(totalDuration: 20, testDurations: [:]),
            configuredTimeout: 30
        )

        #expect(timeout.seconds(forSelection: nil) == 20 * MutantTimeout.baselineCoefficient)
    }

    @Test(
        "Given a suite far faster than the configured timeout, when computed, then the configured timeout is the floor")
    func fastBaselineKeepsTheConfiguredFloor() {
        let timeout = MutantTimeout(
            baseline: BaselineMeasurement(totalDuration: 0.002, testDurations: [:]),
            configuredTimeout: 30
        )

        #expect(timeout.seconds(forSelection: nil) == 30)
    }

    @Test("Given a mutant selecting part of the suite, when computed, then only that selection's baseline counts")
    func selectionIsMeasuredAgainstItsOwnBaseline() {
        let timeout = MutantTimeout(
            baseline: BaselineMeasurement(
                totalDuration: 100,
                testDurations: ["FooTests/testOne": 8, "BarTests/testTwo": 90]
            ),
            configuredTimeout: 30
        )

        #expect(timeout.seconds(forSelection: "FooTests") == 8 * MutantTimeout.baselineCoefficient)
    }
}
