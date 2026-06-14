import Foundation

/// Stable per-device register id sent to the server (`tablet-{uuid}`).
enum RegisterIdLogic {
    static func registerId(vendorUUID: String?) -> String {
        let trimmed = vendorUUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "tablet-unknown"
        }
        return "tablet-\(trimmed)"
    }
}
