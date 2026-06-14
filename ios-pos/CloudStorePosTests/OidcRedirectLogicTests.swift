import XCTest
@testable import CloudStorePos

final class OidcRedirectLogicTests: XCTestCase {
    private let base = URL(string: "https://oci.cloudstore893.com/")!

    func testIsCashierOidcCompleteAwaitingTill() {
        let url = URL(string: "https://oci.cloudstore893.com/?awaiting_till=1")!
        XCTAssertTrue(OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testIsCashierOidcCompletePendingApproval() {
        let url = URL(string: "https://oci.cloudstore893.com/?approval=pending&request_token=abc")!
        XCTAssertTrue(OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testIsCashierOidcCompleteCashierResume() {
        let url = URL(string: "https://oci.cloudstore893.com/?cashier_resume=1")!
        XCTAssertTrue(OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testIsCashierOidcCompleteWebResumedMarker() {
        let url = URL(string: "https://oci.cloudstore893.com/?resumed=1")!
        XCTAssertTrue(OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testIsCashierOidcCompleteAppRootLanding() {
        let url = URL(string: "https://oci.cloudstore893.com/")!
        XCTAssertTrue(OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testIsCashierOidcCompleteRejectsForeignHost() {
        let url = URL(string: "https://evil.example/?cashier_resume=1")!
        XCTAssertFalse(OidcRedirectLogic.isCashierOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testParsePendingRequestToken() {
        let url = URL(string: "https://oci.cloudstore893.com/?approval=pending&request_token=tok123")!
        XCTAssertEqual(OidcRedirectLogic.parsePendingRequestToken(from: url), "tok123")
    }

    func testSyncProbeURLsIncludesCallback() {
        let urls = OidcRedirectLogic.syncProbeURLs(baseURL: base)
        XCTAssertTrue(urls.contains { $0.path == "/oauth/callback" })
    }
}
