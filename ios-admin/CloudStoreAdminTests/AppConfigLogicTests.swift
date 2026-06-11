import XCTest
@testable import CloudStoreAdmin

final class AppConfigLogicTests: XCTestCase {
    func testNormalizeBaseURLStringAddsTrailingSlash() {
        XCTAssertEqual(
            AppConfigLogic.normalizeBaseURLString("https://oci.cloudstore893.com"),
            "https://oci.cloudstore893.com/"
        )
    }

    func testNormalizeBaseURLStringTrimsWhitespace() {
        XCTAssertEqual(
            AppConfigLogic.normalizeBaseURLString("  http://192.168.1.5:3000/  "),
            "http://192.168.1.5:3000/"
        )
    }

    func testAdminURLAddsIosClientKindForEmbeddedApp() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.adminURL(base: base, embeddedIosClient: true, cacheBust: "42")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/admin/")
        XCTAssertEqual(query["client_kind"], "ios")
        XCTAssertEqual(query["_cb"], "42")
    }

    func testAdminURLOmitsClientKindForBrowser() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.adminURL(base: base, embeddedIosClient: false)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/admin/")
        XCTAssertNil(components.queryItems)
    }
}
