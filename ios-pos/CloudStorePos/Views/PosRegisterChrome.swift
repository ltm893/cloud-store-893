import SwiftUI

struct PosRegisterTopBar: View {
    let user: String
    let onMenuTap: () -> Void

    var body: some View {
        ZStack {
            Text("Cloud Store 893 POS")
                .font(.title2.bold())
                .foregroundStyle(PosColors.cream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: 8) {
                Button(action: onMenuTap) {
                    Text("☰")
                        .font(.title2.bold())
                        .foregroundStyle(PosColors.cream)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text("user: \(user)")
                        .font(.caption2)
                        .foregroundStyle(PosColors.cream.opacity(0.92))
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .trailing)
                    Text("v\(AppConfig.appVersion)")
                        .font(.caption2)
                        .foregroundStyle(PosColors.cream)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 5)
        .padding(.bottom, 12)
        .background(PosColors.burgundy)
    }
}

struct PosNavigationDrawer<Content: View, Menu: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var menu: () -> Menu
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            content()

            if isOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { closeDrawer() }
                    .zIndex(1)
            }

            if isOpen {
                menu()
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .background(PosColors.cream)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 2, y: 0)
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isOpen)
    }

    private func closeDrawer() {
        isOpen = false
    }
}

struct PosDrawerMenuButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PosColors.burgundy, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
