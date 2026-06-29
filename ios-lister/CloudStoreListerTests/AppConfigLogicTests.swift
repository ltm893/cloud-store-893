import XCTest
@testable import CloudStoreLister

final class AppConfigLogicTests: XCTestCase {
    func testNormalizeBaseURLAddsTrailingSlash() {
        XCTAssertEqual(AppConfigLogic.normalizeBaseURLString("https://example.com"), "https://example.com/")
    }

    func testInventoryLookupURLBuildsQuery() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = try XCTUnwrap(AppConfigLogic.inventoryLookupURL(base: base, query: "42"))
        XCTAssertEqual(url.path, "/api/inventory/lookup")
        XCTAssertEqual(url.query, "q=42")
    }
}
