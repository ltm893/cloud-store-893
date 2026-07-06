import Foundation

/// Stable per-device lister id sent to the server (`lister-{uuid}`).
enum RegisterIdLogic {
    static func registerId(vendorUUID: String?) -> String {
        let trimmed = vendorUUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "lister-unknown"
        }
        return "lister-\(trimmed)"
    }
}
