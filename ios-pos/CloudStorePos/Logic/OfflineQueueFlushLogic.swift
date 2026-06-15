import Foundation

enum OfflineQueueFlushLogic {
    struct Result: Equatable {
        var synced: Int
        var droppedStale: Int
        var droppedPermanent: Int
        var remaining: Int
        var lastError: String?
    }

    static func buildStatusMessage(_ result: Result) -> String {
        var parts: [String] = []
        if result.synced > 0 {
            parts.append("Synced \(result.synced) sale(s)")
        }
        if result.droppedStale > 0 {
            parts.append("dropped \(result.droppedStale) old entries (no cart saved)")
        }
        if result.droppedPermanent > 0 {
            parts.append("dropped \(result.droppedPermanent) invalid entries")
        }
        if result.remaining > 0 {
            var pending = "\(result.remaining) still pending"
            if let lastError = result.lastError {
                pending += ": \(lastError)"
            }
            parts.append(pending)
        }
        if parts.isEmpty {
            return "Nothing to sync"
        }
        return parts.joined(separator: " · ")
    }
}
