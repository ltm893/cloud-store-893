import XCTest
@testable import CloudStorePos

final class CartTotalsLogicTests: XCTestCase {
    private func item(
        qty: Int = 1,
        publicLine: Double = 10,
        payable: Double = 10,
        taxExempt: Bool = false
    ) -> CartItem {
        CartItem(
            id: 1,
            productId: 1,
            name: "Test",
            regularPrice: 10,
            salePrice: nil,
            onSale: false,
            quantity: qty,
            unitPricePublic: 10,
            unitPricePayable: payable / Double(qty),
            lineSubtotalPublic: publicLine,
            lineSubtotalPayable: payable,
            taxExempt: taxExempt
        )
    }

    func testComputeSaleGrandTotalWithTax() {
        let total = CartTotalsLogic.computeSaleGrandTotal(
            cart: [item(publicLine: 100, payable: 100)],
            salesFeeRate: 0,
            taxRate: 0.06
        )
        XCTAssertEqual(total, 106, accuracy: 0.01)
    }

    func testComputeSaleGrandTotalSkipsTaxOnExemptItems() {
        let total = CartTotalsLogic.computeSaleGrandTotal(
            cart: [
                item(publicLine: 10, payable: 10),
                item(publicLine: 5, payable: 5, taxExempt: true),
            ],
            salesFeeRate: 0,
            taxRate: 0.06
        )
        XCTAssertEqual(total, 15.6, accuracy: 0.01)
    }

    func testLinkedCustomerTaxExemptWaterHasNoTax() {
        let total = CartTotalsLogic.computeSaleGrandTotal(
            cart: [item(publicLine: 1.99, payable: 1.79, taxExempt: true)],
            customerLinked: true,
            customerDiscount: true,
            salesFeeRate: 0,
            taxRate: 0.06
        )
        XCTAssertEqual(total, 1.79, accuracy: 0.01)
        let tax = CartTotalsLogic.computeTaxAmount(
            cart: [item(publicLine: 1.99, payable: 1.79, taxExempt: true)],
            customerLinked: true,
            customerDiscount: true,
            salesFeeRate: 0,
            taxRate: 0.06
        )
        XCTAssertEqual(tax, 0, accuracy: 0.001)
    }

    func testBuildCashPaymentWithChange() {
        let payment = CheckoutPaymentLogic.buildCheckoutPaymentLine(
            method: "cash",
            enteredAmount: 20,
            balanceDue: 15.50
        )
        XCTAssertNotNil(payment)
        XCTAssertEqual(payment?.amount ?? 0, 15.5, accuracy: 0.01)
        XCTAssertEqual(payment?.changeGiven ?? 0, 4.5, accuracy: 0.01)
    }

    func testRejectCardOverBalance() {
        let payment = CheckoutPaymentLogic.buildCheckoutPaymentLine(
            method: "card",
            enteredAmount: 20,
            balanceDue: 15
        )
        XCTAssertNil(payment)
    }

    func testCheckoutFinalizeMethodSplit() {
        let payments = [
            CheckoutPayment(method: "cash", amount: 5, tenderedAmount: 5, changeGiven: nil),
            CheckoutPayment(method: "card", amount: 10, tenderedAmount: 10, changeGiven: nil),
        ]
        XCTAssertEqual(CheckoutPaymentLogic.checkoutFinalizeMethod(payments), "split")
    }

    func testIsCheckoutCompleteWithNickelCashRemainder() {
        let registerTotal = 10.06
        let payments = [
            CheckoutPayment(method: "card", amount: 5, tenderedAmount: 5, changeGiven: nil),
            CheckoutPayment(method: "cash", amount: 5.05, tenderedAmount: 5.05, changeGiven: nil),
        ]
        XCTAssertTrue(CheckoutPaymentLogic.isCheckoutComplete(registerTotal: registerTotal, payments: payments))
    }

    func testRemainingCashAmountDueRoundsSplitRemainder() {
        XCTAssertEqual(
            CartTotalsLogic.remainingCashAmountDue(registerTotal: 10.06, nonCashPaid: 5),
            5.05,
            accuracy: 0.001
        )
    }

    func testAppendQuantityDigitCapsAtFourDigits() {
        XCTAssertEqual(CashEntryLogic.appendQuantityDigit(current: "123", digit: "4"), "1234")
        XCTAssertEqual(CashEntryLogic.appendQuantityDigit(current: "1234", digit: "5"), "1234")
        XCTAssertEqual(CashEntryLogic.appendQuantityDigit(current: "", digit: "a"), "")
    }
}
