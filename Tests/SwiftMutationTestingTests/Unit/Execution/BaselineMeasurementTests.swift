import Testing

@testable import SwiftMutationTesting

@Suite("BaselineMeasurement")
struct BaselineMeasurementTests {
    private let measurement = BaselineMeasurement(
        totalDuration: 9.0,
        testDurations: [
            "FooTests/testOne": 1.0,
            "FooTests/testTwo": 2.0,
            "BarTests/testThree": 4.0,
        ]
    )

    @Test("Given no selection, when the duration is asked for, then the whole run's duration is returned")
    func noSelectionMeasuresTheWholeRun() {
        #expect(measurement.duration(ofSelection: nil) == 9.0)
    }

    @Test("Given a selection naming a class, when the duration is asked for, then its tests are summed")
    func classSelectionSumsItsTests() {
        #expect(measurement.duration(ofSelection: "FooTests") == 3.0)
    }

    @Test("Given a selection naming a single test, when the duration is asked for, then only that test counts")
    func methodSelectionMeasuresOneTest() {
        #expect(measurement.duration(ofSelection: "FooTests/testTwo") == 2.0)
    }

    @Test("Given a selection naming several classes, when the duration is asked for, then all of them are summed")
    func commaSeparatedSelectionSumsEveryClass() {
        #expect(measurement.duration(ofSelection: "FooTests,BarTests") == 7.0)
    }

    @Test("Given a selection no measured test matched, when the duration is asked for, then the whole run's stands")
    func unmatchedSelectionFallsBackToTheWholeRun() {
        #expect(measurement.duration(ofSelection: "MissingTests") == 9.0)
    }
}
