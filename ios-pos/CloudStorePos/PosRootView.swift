import SwiftUI

struct PosRootView: View {
    @State private var viewModel = PosSessionViewModel()

    var body: some View {
        ZStack {
            Color(red: 250 / 255, green: 243 / 255, blue: 223 / 255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !hidesChromeHeader {
                    headerBar
                }
                gateContent
            }
        }
        .onAppear {
            viewModel.probeSessionOnLaunch()
        }
    }

    private var headerBar: some View {
        VStack(spacing: 2) {
            Text("Cloud Store POS")
                .font(.caption.bold())
                .foregroundStyle(Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255))
            Text("\(AppConfig.apiHostLabel) · \(AppConfig.registerId)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(viewModel.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
    }

    private var hidesChromeHeader: Bool {
        isOpeningTillGate || isSignedInGate
    }

    private var isOpeningTillGate: Bool {
        if case .openingTill = viewModel.authGate { return true }
        return false
    }

    private var isSignedInGate: Bool {
        if case .signedIn = viewModel.authGate { return true }
        return false
    }

    @ViewBuilder
    private var gateContent: some View {
        switch viewModel.authGate {
        case .checking:
            ProgressView("Checking session…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .signIn(let pinAllowed, let idpEnabled):
            signInContent(pinAllowed: pinAllowed, idpEnabled: idpEnabled)

        case .oidcSignIn:
            OidcSignInScreen(
                loginURL: viewModel.oidcLoginURL,
                apiBaseURL: AppConfig.apiBaseURL,
                onComplete: { viewModel.onOidcWebViewComplete(completionURL: $0) },
                onCancel: { viewModel.cancelOidcSignIn() }
            )

        case .signedIn(let user):
            RegisterScreen(
                user: user,
                session: viewModel,
                onBreak: { viewModel.signOutForBreak() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .waitingApproval(
            let email,
            let secondsRemaining,
            let cashMode,
            let expectedOpeningFloat,
            let openingCountedFloat,
            let openingVariance
        ):
            waitingApprovalContent(
                email: email,
                secondsRemaining: secondsRemaining,
                cashMode: cashMode,
                expectedOpeningFloat: expectedOpeningFloat,
                openingCountedFloat: openingCountedFloat,
                openingVariance: openingVariance
            )

        case .openingTill(
            let expectedOpeningFloat,
            let denominations,
            let counts,
            let selectedDenominationId,
            let submitting
        ):
            OpeningTillScreen(
                expectedOpeningFloat: expectedOpeningFloat,
                denominations: denominations,
                counts: counts,
                selectedDenominationId: selectedDenominationId,
                status: viewModel.status,
                submitting: submitting,
                onSelectDenomination: { viewModel.selectTillDenomination($0) },
                onDigit: { viewModel.appendTillDigit($0) },
                onClearCount: { viewModel.clearTillCount() },
                onBackspaceCount: { viewModel.backspaceTillCount() },
                onPreviousDenomination: { viewModel.selectPreviousTillDenomination() },
                onNextDenomination: { viewModel.selectNextTillDenomination() },
                onSubmit: { viewModel.submitOpeningTill() },
                onNoCashToday: { viewModel.submitNoCashToday() },
                onCancel: { viewModel.cancelOpeningTill() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func signInContent(pinAllowed: Bool, idpEnabled: Bool) -> some View {
        VStack(spacing: 16) {
            Text("Cashier sign-in")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255))

            if viewModel.status.localizedCaseInsensitiveContains("break") {
                Text(viewModel.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if idpEnabled || !pinAllowed {
                Button("Sign in with Oracle") {
                    viewModel.openOidcSignIn()
                }
                .buttonStyle(PosPrimaryButtonStyle())
            }

            if pinAllowed {
                Text("PIN sign-in available when supervisor approval is off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Retry session check") {
                viewModel.recheckSession()
            }
            .font(.footnote)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waitingApprovalContent(
        email: String?,
        secondsRemaining: Int?,
        cashMode: String?,
        expectedOpeningFloat: Double?,
        openingCountedFloat: Double?,
        openingVariance: Double?
    ) -> some View {
        VStack(spacing: 16) {
            Text("Till open — waiting for supervisor")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let timer = TillApprovalSummaryLogic.approvalTimerText(secondsRemaining: secondsRemaining) {
                Text(timer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let summary = TillApprovalSummaryLogic.openingSummaryLine(
                cashMode: cashMode,
                counted: openingCountedFloat,
                expected: expectedOpeningFloat,
                variance: openingVariance
            ) {
                Text(summary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: 480)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let email, !email.isEmpty {
                Text(email)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ProgressView()
                .padding(.top, 8)

            Button("Cancel") {
                viewModel.cancelApprovalWait()
            }
            .font(.headline)
            .foregroundStyle(Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PosPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(red: 0 / 255, green: 109 / 255, blue: 119 / 255))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    PosRootView()
}
