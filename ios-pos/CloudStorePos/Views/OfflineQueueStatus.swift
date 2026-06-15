import SwiftUI

struct OfflineQueueStatus: View {
    let queuedCount: Int
    let syncing: Bool
    let onSyncQueued: () -> Void
    let onDiscardQueued: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Offline queue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PosColors.burgundy)

            if queuedCount > 0 {
                Text("Queued checkouts: \(queuedCount)")
                    .font(.subheadline)
                Text("Sync replays each saved cart. Discard clears entries that cannot be recovered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(syncing ? "Syncing…" : "Sync queued") {
                    onSyncQueued()
                }
                .buttonStyle(PosOutlinedQuickButtonStyle())
                .disabled(syncing)
                Button("Discard queue") {
                    onDiscardQueued()
                }
                .buttonStyle(PosOutlinedQuickButtonStyle())
                .disabled(syncing)
            } else {
                Text("No queued checkouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
