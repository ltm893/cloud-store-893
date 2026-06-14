import Foundation

/// API host baked in at build time (mirrors Android `BuildConfig.API_BASE_URL`).
enum AppConfig {
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://oci.cloudstore893.com/"
        return AppConfigLogic.apiBaseURL(fromRaw: raw)
    }

    static var apiHostLabel: String {
        apiBaseURL.host ?? apiBaseURL.absoluteString
    }

    static var registerId: String {
        RegisterId.current
    }

    static var salesFeeRate: Double {
        let raw = Bundle.main.object(forInfoDictionaryKey: "POS_SALES_FEE_RATE") as? String ?? "0.0"
        return Double(raw) ?? 0
    }

    static var taxRate: Double {
        let raw = Bundle.main.object(forInfoDictionaryKey: "POS_TAX_RATE") as? String ?? "0.06"
        return Double(raw) ?? 0.06
    }

    static var oidcLoginURL: URL {
        AppConfigLogic.oidcLoginURL(base: apiBaseURL, registerId: registerId)
    }
}
