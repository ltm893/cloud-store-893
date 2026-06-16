import SwiftUI

struct RegisterStatusPanel: View {
    let apiBaseURL: String
    let tillId: Int?
    let posSessionId: Int?
    let statusMessage: String
    let queuedCount: Int
    let syncing: Bool
    let onSyncQueued: () -> Void
    let onDiscardQueued: () -> Void

    private var sessionLine: String? {
        var parts: [String] = []
        if let tillId {
            parts.append("Till #\(tillId)")
        }
        if let posSessionId {
            parts.append("POS session #\(posSessionId)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PosColors.burgundy)

            VStack(alignment: .leading, spacing: 2) {
                Text("API URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(apiBaseURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let sessionLine {
                Text(sessionLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            OfflineQueueStatus(
                queuedCount: queuedCount,
                syncing: syncing,
                onSyncQueued: onSyncQueued,
                onDiscardQueued: onDiscardQueued
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .posPanelStyle()
    }
}
