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

    func testOidcLoginURLAddsListerClientKindAndRegisterId() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.oidcLoginURL(
            base: base,
            registerId: "lister-550E8400-E29B-41D4-A716-446655440000"
        )
        XCTAssertEqual(url.path, "/oauth/login")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_kind"], "lister")
        XCTAssertEqual(query["register_id"], "lister-550E8400-E29B-41D4-A716-446655440000")
    }
}
