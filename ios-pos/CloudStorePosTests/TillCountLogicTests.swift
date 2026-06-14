import XCTest
@testable import CloudStorePos

final class TillCountLogicTests: XCTestCase {
    private let denoms: [TillDenomination] = [
        TillDenomination(id: "20", label: "$20", value: 20),
        TillDenomination(id: "5", label: "$5", value: 5),
        TillDenomination(id: "1", label: "$1", value: 1),
    ]

    func testSumTillCounts() {
        let counts = ["20": "2", "5": "1", "1": "3"]
        XCTAssertEqual(TillCountLogic.sumTillCounts(denominations: denoms, counts: counts), 48)
    }

    func testRoundMoney() {
        XCTAssertEqual(TillCountLogic.roundMoney(40), 40)
        XCTAssertEqual(TillCountLogic.roundMoney(10.125), 10.13, accuracy: 0.001)
        XCTAssertEqual(TillCountLogic.roundMoney(10.124), 10.12, accuracy: 0.001)
    }

    func testCanSubmitWhenTargetReached() {
        let counts = ["20": "2", "5": "0", "1": "0"]
        XCTAssertTrue(
            TillCountLogic.canSubmit(
                expectedOpeningFloat: 40,
                denominations: denoms,
                counts: counts
            )
        )
    }

    func testCannotSubmitWhenUnderTarget() {
        let counts = ["20": "1"]
        XCTAssertFalse(
            TillCountLogic.canSubmit(
                expectedOpeningFloat: 40,
                denominations: denoms,
                counts: counts
            )
        )
    }

    func testActionStatusNeedMore() {
        let status = TillCountLogic.actionStatus(
            expectedOpeningFloat: 40,
            denominations: denoms,
            counts: ["20": "1"],
            submitting: false,
            status: "Count opening till"
        )
        XCTAssertEqual(status, "Need $20.00 more")
    }
}
