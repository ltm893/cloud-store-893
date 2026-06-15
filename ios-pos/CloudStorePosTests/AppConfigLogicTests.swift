import XCTest
@testable import CloudStorePos

final class AppConfigLogicTests: XCTestCase {
    func testNormalizeBaseURLStringAddsTrailingSlash() {
        XCTAssertEqual(
            AppConfigLogic.normalizeBaseURLString("https://oci.cloudstore893.com"),
            "https://oci.cloudstore893.com/"
        )
    }

    func testOidcLoginURLAddsIosClientKindAndRegisterId() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.oidcLoginURL(
            base: base,
            registerId: "tablet-550E8400-E29B-41D4-A716-446655440000"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/oauth/login")
        XCTAssertEqual(query["client_kind"], "ios")
        XCTAssertEqual(query["register_id"], "tablet-550E8400-E29B-41D4-A716-446655440000")
        XCTAssertNil(query["prompt"])
    }

    func testOidcLoginURLAddsPromptLoginWhenFresh() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.oidcLoginURL(
            base: base,
            registerId: "tablet-abc",
            freshLogin: true
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(query["prompt"], "login")
    }

    func testApiRequestURLBuildsQueryItemsSeparatelyFromPath() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = try XCTUnwrap(
            AppConfigLogic.apiRequestURL(
                base: base,
                path: "api/cashier/shift/close/status",
                queryItems: [URLQueryItem(name: "closeToken", value: "abc123")]
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/api/cashier/shift/close/status")
        XCTAssertEqual(query["closeToken"], "abc123")
        XCTAssertFalse(url.absoluteString.contains("%3F"))
    }

    func testAdminURLAddsIosClientKind() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.adminURL(base: base, embeddedIosClient: true, cacheBust: "42")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/admin/")
        XCTAssertEqual(query["client_kind"], "ios")
        XCTAssertEqual(query["_cb"], "42")
    }

    func testShouldLeaveAdminOnSiteRoot() {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        XCTAssertTrue(AdminNavigationLogic.shouldLeaveAdmin(
            url: URL(string: "https://oci.cloudstore893.com/")!,
            apiBaseURL: base
        ))
        XCTAssertFalse(AdminNavigationLogic.shouldLeaveAdmin(
            url: URL(string: "https://oci.cloudstore893.com/admin/")!,
            apiBaseURL: base
        ))
    }
}
