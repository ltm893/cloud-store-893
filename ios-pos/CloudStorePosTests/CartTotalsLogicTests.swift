import XCTest
@testable import CloudStorePos

final class CartTotalsLogicTests: XCTestCase {
    private func item(qty: Int = 1, publicLine: Double = 10, payable: Double = 10) -> CartItem {
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
            lineSubtotalPayable: payable
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
}
