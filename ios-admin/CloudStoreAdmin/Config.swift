import Foundation
import UIKit

/// API host baked in at build time (mirrors Android `BuildConfig.API_BASE_URL`).
enum AppConfig {
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://oci.cloudstore893.com/"
        return AppConfigLogic.apiBaseURL(fromRaw: raw)
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var adminURL: URL {
        // Native WKWebView — always tag client_kind=ios (skips landscape-only overlay).
        AppConfigLogic.adminURL(
            base: apiBaseURL,
            embeddedIosClient: true,
            cacheBust: appBuild
        )
    }

    static var apiHostLabel: String {
        apiBaseURL.host ?? apiBaseURL.absoluteString
    }
}
