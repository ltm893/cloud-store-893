import XCTest
@testable import CloudStorePos

final class InfoPlistTests: XCTestCase {
    private var appInfoPlist: [String: Any] {
        get throws {
            let bundle = try XCTUnwrap(
                Bundle.allBundles.first(where: { $0.bundleIdentifier == "com.cloudstore.pos" })
            )
            let url = try XCTUnwrap(bundle.url(forResource: "Info", withExtension: "plist"))
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
        }
    }

    func testInfoPlistDefinesAPIBaseURL() throws {
        let value = try XCTUnwrap(appInfoPlist["API_BASE_URL"] as? String)
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotNil(URL(string: value.hasSuffix("/") ? value : "\(value)/"))
    }

    func testIPadSupportsLandscapeOnly() throws {
        let orientations = try XCTUnwrap(
            appInfoPlist["UISupportedInterfaceOrientations"] as? [String]
        )
        XCTAssertEqual(orientations, [
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ])
    }
}
