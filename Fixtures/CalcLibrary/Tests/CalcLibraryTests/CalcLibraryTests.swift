import XCTest

@testable import CalcLibrary

final class CalcLibraryTests: XCTestCase {
    func testAdd() {
        XCTAssertEqual(Calculator().add(2, 3), 5)
    }

    func testSubtract() {
        XCTAssertEqual(Calculator().subtract(5, 3), 2)
    }

    func testIsPositive() {
        XCTAssertTrue(Calculator().isPositive(1))
    }

    func testIsInRange() {
        XCTAssertTrue(Validator().isInRange(50))
        XCTAssertFalse(Validator().isInRange(-1))
        XCTAssertTrue(Validator().isInRange(0))
    }

    func testRaceTargetIsPositiveTrueOnly() {
        XCTAssertTrue(RaceTarget().isPositive(1))
    }

    func testRaceTargetIsZeroBoundaries() {
        XCTAssertTrue(RaceTarget().isZero(0))
        XCTAssertFalse(RaceTarget().isZero(1))
        XCTAssertFalse(RaceTarget().isZero(-1))
    }

    func testRaceTargetCountUp() {
        XCTAssertEqual(RaceTarget().countUp(to: 5), 5)
    }

    func testTimeoutTargetMaybeStallInstantPath() {
        XCTAssertEqual(TimeoutTarget().maybeStall(1), 1)
        XCTAssertEqual(TimeoutTarget().maybeStall(5), 5)
    }

    func testUnaffectedSlowMutantMaybeDelay() {
        XCTAssertEqual(UnaffectedSlowMutant().maybeDelay(1), 1)
    }
}
