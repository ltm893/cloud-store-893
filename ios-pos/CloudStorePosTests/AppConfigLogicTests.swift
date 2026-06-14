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
}
