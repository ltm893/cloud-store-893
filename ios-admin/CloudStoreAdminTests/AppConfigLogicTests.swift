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

    func testAdminURLAddsIosClientKindForPortraitClient() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.adminURL(base: base, portraitClient: true)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/admin/")
        XCTAssertEqual(components.queryItems?.first?.name, "client_kind")
        XCTAssertEqual(components.queryItems?.first?.value, "ios")
    }

    func testAdminURLOmitsClientKindForTabletClient() throws {
        let base = URL(string: "https://oci.cloudstore893.com/")!
        let url = AppConfigLogic.adminURL(base: base, portraitClient: false)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/admin/")
        XCTAssertNil(components.queryItems)
    }
}
