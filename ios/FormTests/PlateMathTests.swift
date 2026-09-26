import XCTest
@testable import Form

final class PlateMathTests: XCTestCase {
    func testLoadsGreedyPerSide() {
        XCTAssertEqual(PlateMath.plates(total: 82.5, bar: 20), [.p25, .p5, .p1_25])
        XCTAssertEqual(PlateMath.plates(total: 85, bar: 20), [.p25, .p5, .p2_5])
        XCTAssertEqual(PlateMath.plates(total: 90, bar: 20), [.p25, .p10])
        XCTAssertEqual(PlateMath.plates(total: 140, bar: 20), [.p25, .p25, .p10])
    }

    func testJustTheBar() {
        XCTAssertEqual(PlateMath.plates(total: 20, bar: 20), [])
    }

    func testImpossibleWeights() {
        XCTAssertNil(PlateMath.plates(total: 15, bar: 20))
        XCTAssertNil(PlateMath.plates(total: 21, bar: 20))
    }

    func testEZBar() {
        XCTAssertEqual(PlateMath.plates(total: 30, bar: 10), [.p10])
    }

    func testEpley() {
        XCTAssertEqual(PlateMath.estimatedOneRepMax(weight: 100, reps: 1), 100)
        XCTAssertEqual(PlateMath.estimatedOneRepMax(weight: 82.5, reps: 8), 104.5, accuracy: 0.01)
        XCTAssertEqual(PlateMath.estimatedOneRepMax(weight: 80, reps: 0), 0)
    }

    func testKgFormatting() {
        XCTAssertEqual(82.5.kg, "82.5")
        XCTAssertEqual(80.0.kg, "80")
        XCTAssertEqual(1.25.kg, "1.25")
    }
}
