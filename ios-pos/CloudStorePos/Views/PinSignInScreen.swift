import SwiftUI

struct PinSignInScreen: View {
    let pinInput: String
    let pinAllowed: Bool
    let idpEnabled: Bool
    let status: String
    let onDigit: (Character) -> Void
    let onClear: () -> Void
    let onBackspace: () -> Void
    let onUnlock: () -> Void
    let onOidcSignIn: () -> Void
    let onRetrySession: () -> Void

    private var showStatus: Bool {
        !status.isEmpty
            && status != "Ready"
            && !status.localizedCaseInsensitiveContains("checking session")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Cashier sign-in")
                .font(.title2.bold())
                .foregroundStyle(PosColors.burgundy)

            if showStatus {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 12) {
                if pinAllowed {
                    Text(PinSignInLogic.maskedPin(pinInput))
                        .font(.title.monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("PIN entry")

                    PosNumberPad(
                        layout: .compact,
                        onDigit: onDigit,
                        onClear: onClear,
                        onBackspace: onBackspace
                    )
                    .padding(PosLayoutMetrics.numpadInnerPadding)
                    .frame(width: PosLayoutMetrics.numpadColumnWidth)
                    .frame(height: PosLayoutMetrics.numpadCardHeight)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("Done") { onUnlock() }
                        .buttonStyle(PosFullWidthButtonStyle())
                        .frame(width: PosLayoutMetrics.numpadColumnWidth)
                }

                if idpEnabled {
                    Button("Sign in with Oracle") { onOidcSignIn() }
                        .buttonStyle(PosPrimaryButtonStyle())
                        .padding(.top, pinAllowed ? 4 : 0)
                }
            }

            Button("Retry session check", action: onRetrySession)
                .font(.footnote)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
