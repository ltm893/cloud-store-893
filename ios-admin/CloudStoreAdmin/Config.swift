import Foundation
import UIKit

/// API host baked in at build time (mirrors Android `BuildConfig.API_BASE_URL`).
enum AppConfig {
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://oci.cloudstore893.com/"
        return AppConfigLogic.apiBaseURL(fromRaw: raw)
    }

    static var adminURL: URL {
        AppConfigLogic.adminURL(
            base: apiBaseURL,
            portraitClient: UIDevice.current.userInterfaceIdiom == .phone
        )
    }
}
