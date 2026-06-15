import XCTest
@testable import CloudStorePos

final class CustomerFindLogicTests: XCTestCase {
    private func customer(id: Int, name: String, email: String? = nil) -> StoreCustomer {
        StoreCustomer(
            id: id,
            name: name,
            email: email,
            phone: nil,
            memberCode: nil,
            is893: true,
            hasCardOnFile: false,
            cardLast4: nil
        )
    }

    func testFilterMatchesByName() {
        let customers = [customer(id: 1, name: "Jane Doe", email: "jane@example.com")]
        let matches = CustomerFindLogic.filterMatches(customers: customers, query: "jane")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.id, 1)
    }

    func testFilterMatchesByIdPrefix() {
        let customers = [
            customer(id: 12, name: "A"),
            customer(id: 120, name: "B"),
            customer(id: 9, name: "C"),
        ]
        let matches = CustomerFindLogic.filterMatches(customers: customers, query: "12")
        XCTAssertEqual(matches.map(\.id), [12, 120])
    }

    func testDisplayNameFallback() {
        XCTAssertEqual(CustomerFindLogic.displayName(nil, customerId: 7), "Customer #7")
    }
}
