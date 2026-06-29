import Foundation

enum AppConfig {
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://oci.cloudstore893.com/"
        return AppConfigLogic.apiBaseURL(fromRaw: raw)
    }

    static var apiHostLabel: String {
        apiBaseURL.host ?? apiBaseURL.absoluteString
    }
}
