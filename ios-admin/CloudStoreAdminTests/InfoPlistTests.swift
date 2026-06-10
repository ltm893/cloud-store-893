import XCTest
@testable import CloudStoreAdmin

final class InfoPlistTests: XCTestCase {
    private var appInfoPlist: [String: Any] {
        get throws {
            let bundle = Bundle(for: AppDelegate.self)
            let url = try XCTUnwrap(bundle.url(forResource: "Info", withExtension: "plist"))
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
        }
    }

    func testIPhoneSupportsPortraitOnly() throws {
        let orientations = try XCTUnwrap(
            appInfoPlist["UISupportedInterfaceOrientations"] as? [String]
        )
        XCTAssertEqual(orientations, ["UIInterfaceOrientationPortrait"])
    }

    func testIPadSupportsLandscapeOnly() throws {
        let orientations = try XCTUnwrap(
            appInfoPlist["UISupportedInterfaceOrientations~ipad"] as? [String]
        )
        XCTAssertEqual(orientations, [
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ])
    }
}
