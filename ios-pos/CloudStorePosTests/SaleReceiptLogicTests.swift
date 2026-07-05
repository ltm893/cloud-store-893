import XCTest
@testable import CloudStorePos

final class SaleReceiptLogicTests: XCTestCase {
    func testBuildSaleReceiptIncludesLinesAndTotals() {
        let item = CartItem(
            id: 1,
            productId: 101,
            name: "Widget",
            regularPrice: 10,
            salePrice: nil,
            onSale: false,
            quantity: 2,
            unitPricePublic: 10,
            unitPricePayable: 10,
            lineSubtotalPublic: 20,
            lineSubtotalPayable: 20
        )
        let receipt = SaleReceiptLogic.buildSaleReceipt(
            cart: [item],
            customerName: "Pat Example",
            customerLinked: false,
            customerDiscount: false,
            salesFeeRate: 0,
            taxRate: 0.06,
            payments: [CheckoutPayment(method: "cash", amount: 21.2, tenderedAmount: 25, changeGiven: 3.8)],
            orderNumber: "ORD-42"
        )

        XCTAssertEqual(receipt.orderNumber, "ORD-42")
        XCTAssertEqual(receipt.customerName, "Pat Example")
        XCTAssertEqual(receipt.lines.count, 1)
        XCTAssertEqual(receipt.lines[0].productId, 101)
        XCTAssertEqual(receipt.lines[0].quantity, 2)
        XCTAssertEqual(receipt.itemCount, 2)
        XCTAssertEqual(receipt.subtotal, 20)
        XCTAssertEqual(receipt.tax, 1.2)
        XCTAssertEqual(receipt.grandTotal, 21.2)
        XCTAssertEqual(receipt.collectedTotal, 21.2)
        XCTAssertEqual(receipt.changeTotal, 3.8)
        XCTAssertEqual(receipt.orderLabel, "ORD-42")
    }

    func testQueuedOfflineOrderLabel() {
        let receipt = SaleReceiptLogic.buildSaleReceipt(
            cart: [],
            customerName: nil,
            customerLinked: false,
            customerDiscount: false,
            salesFeeRate: 0,
            taxRate: 0,
            payments: [],
            queuedOffline: true
        )
        XCTAssertEqual(receipt.orderLabel, "Queued for sync")
    }

    func testBuildSaleReceiptShowsMemberDiscountForLinkedCustomer() {
        let item = CartItem(
            id: 1,
            productId: 101,
            name: "Widget",
            regularPrice: 10,
            salePrice: nil,
            onSale: false,
            quantity: 2,
            unitPricePublic: 10,
            unitPricePayable: 8,
            lineSubtotalPublic: 20,
            lineSubtotalPayable: 16
        )
        let receipt = SaleReceiptLogic.buildSaleReceipt(
            cart: [item],
            customerName: "Pat Example",
            customerLinked: true,
            customerDiscount: true,
            salesFeeRate: 0,
            taxRate: 0,
            payments: [CheckoutPayment(method: "card", amount: 16)],
            orderNumber: "ORD-99"
        )

        XCTAssertTrue(receipt.customerLinked)
        XCTAssertEqual(receipt.shelfSubtotal, 20)
        XCTAssertEqual(receipt.memberDiscount, 4)
        XCTAssertEqual(receipt.subtotal, 16)
        XCTAssertTrue(receipt.showMemberDiscount)
    }
}
