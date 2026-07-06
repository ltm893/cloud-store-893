import XCTest
@testable import CloudStoreLister

final class ListerOidcRedirectLogicTests: XCTestCase {
    private let base = URL(string: "https://oci.cloudstore893.com/")!

    func testDetectsListerSignedInQuery() {
        let url = URL(string: "https://oci.cloudstore893.com/?lister_signed_in=1")!
        XCTAssertTrue(ListerOidcRedirectLogic.isOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testRejectsOAuthCallbackPath() {
        let url = URL(string: "https://oci.cloudstore893.com/oauth/callback?code=x")!
        XCTAssertFalse(ListerOidcRedirectLogic.isOidcComplete(completionURL: url, apiBaseURL: base))
    }

    func testDetectsAppRootLanding() {
        let url = URL(string: "https://oci.cloudstore893.com/")!
        XCTAssertTrue(ListerOidcRedirectLogic.isOidcComplete(completionURL: url, apiBaseURL: base))
    }
}
