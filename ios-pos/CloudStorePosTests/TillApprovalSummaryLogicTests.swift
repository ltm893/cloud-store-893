import XCTest
@testable import CloudStorePos

final class TillApprovalSummaryLogicTests: XCTestCase {
    func testApprovalTimerTextFormatsMinutesAndSeconds() {
        XCTAssertEqual(TillApprovalSummaryLogic.approvalTimerText(secondsRemaining: 125), "Expires in 2:05")
    }

    func testApprovalTimerTextNilForNegative() {
        XCTAssertNil(TillApprovalSummaryLogic.approvalTimerText(secondsRemaining: -1))
    }

    func testOpeningSummaryCreditOnly() {
        XCTAssertEqual(
            TillApprovalSummaryLogic.openingSummaryLine(
                cashMode: "credit_only",
                counted: nil,
                expected: nil,
                variance: nil
            ),
            "Card only · Card payments only"
        )
    }

    func testOpeningSummaryCashAndCard() {
        let line = TillApprovalSummaryLogic.openingSummaryLine(
            cashMode: "cash_and_credit",
            counted: 200,
            expected: 200,
            variance: 0
        )
        XCTAssertEqual(line, "Cash + card · Opening $200.00")
    }

    func testActiveTillLineCreditOnly() {
        XCTAssertEqual(
            TillApprovalSummaryLogic.activeTillLine(cashMode: "credit_only", tillId: 42),
            "Active till #42 · Card payments only"
        )
    }

    func testClosingSummaryWithVariance() {
        let line = TillApprovalSummaryLogic.closingSummaryLine(
            cashMode: "cash_and_credit",
            counted: 215,
            expected: 200,
            variance: 15
        )
        XCTAssertEqual(
            line,
            "Cash + card · Counted $215.00 · Expected $200.00 · Variance +$15.00"
        )
    }
}

final class ApprovalStatusResponseTests: XCTestCase {
    func testDecodesApprovedPollResponse() throws {
        let json = """
        {"status":"approved","ok":true,"email":"cashier@example.com"}
        """
        let decoded = try JSONDecoder().decode(
            ApprovalStatusResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.status, "approved")
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.displayEmail, "cashier@example.com")
    }
}
