import SwiftUI

struct AdminWebScreen: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("← Register", action: onClose)
                    .font(.subheadline.bold())
                    .foregroundStyle(PosColors.burgundy)
                Text("Admin")
                    .font(.headline.bold())
                    .foregroundStyle(PosColors.burgundy)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PosColors.cream)

            PosAdminWebView(apiBaseURL: AppConfig.apiBaseURL, onLeaveAdmin: onClose)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PosColors.cream)
    }
}
