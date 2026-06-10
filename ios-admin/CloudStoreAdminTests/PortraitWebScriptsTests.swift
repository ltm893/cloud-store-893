import XCTest
@testable import CloudStoreAdmin

final class PortraitWebScriptsTests: XCTestCase {
    func testDocumentStartScriptHidesPortraitBlocker() {
        XCTAssertTrue(PortraitWebScripts.documentStart.contains("admin-portrait-ok"))
        XCTAssertTrue(PortraitWebScripts.documentStart.contains("portrait-blocker"))
        XCTAssertTrue(PortraitWebScripts.documentStart.contains("display: none !important"))
    }

    func testApplyAfterLoadRemovesLandscapeClassAndBlocker() {
        XCTAssertTrue(PortraitWebScripts.applyAfterLoad.contains("admin-landscape"))
        XCTAssertTrue(PortraitWebScripts.applyAfterLoad.contains("portraitBlocker"))
        XCTAssertTrue(PortraitWebScripts.applyAfterLoad.contains("remove()"))
    }
}
