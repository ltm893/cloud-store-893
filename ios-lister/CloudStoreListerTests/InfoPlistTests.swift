import XCTest
@testable import CloudStoreLister

final class InfoPlistTests: XCTestCase {
    private var appInfoPlist: [String: Any] {
        get throws {
            let bundle = Bundle(for: AppConfigLogicTests.self)
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
}
