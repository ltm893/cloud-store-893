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
        .alert("Notice", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.clearAlert() } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.clearAlert()
            }
        } message: {
            Text(viewModel.alertMessage ?? "")
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
        isTillFlowGate || isSignedInGate
    }

    private var isTillFlowGate: Bool {
        switch viewModel.authGate {
        case .openingTill, .closingTill, .closingCreditOnly, .waitingCloseApproval:
            return true
        default:
            return false
        }
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
            PinSignInScreen(
                pinInput: viewModel.pinInput,
                pinAllowed: pinAllowed,
                idpEnabled: idpEnabled,
                status: viewModel.status,
                onDigit: { viewModel.appendPinDigit($0) },
                onClear: { viewModel.clearPinInput() },
                onBackspace: { viewModel.backspacePinInput() },
                onUnlock: { viewModel.unlockWithPin() },
                onOidcSignIn: { viewModel.openOidcSignIn() },
                onRetrySession: { viewModel.recheckSession() }
            )

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
                onBreak: { viewModel.signOutForBreak() },
                onCloseTill: { viewModel.beginCloseTill() }
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

        case .closingTill(
            let expectedCloseFloat,
            let openingCountedFloat,
            let cashSalesTotal,
            let changeGivenTotal,
            let denominations,
            let counts,
            let selectedDenominationId,
            let submitting
        ):
            OpeningTillScreen(
                expectedOpeningFloat: expectedCloseFloat,
                denominations: denominations,
                counts: counts,
                selectedDenominationId: selectedDenominationId,
                status: viewModel.status,
                submitting: submitting,
                options: TillCountScreenOptions.closing(
                    headerHint: TillCountLogic.closingHeaderHint(
                        openingCountedFloat: openingCountedFloat,
                        cashSalesTotal: cashSalesTotal,
                        changeGivenTotal: changeGivenTotal
                    ),
                    supervisorApprovalRequired: viewModel.closeSupervisorApprovalRequired
                ),
                onSelectDenomination: { viewModel.selectClosingDenomination($0) },
                onDigit: { viewModel.appendClosingTillDigit($0) },
                onClearCount: { viewModel.clearClosingTillCount() },
                onBackspaceCount: { viewModel.backspaceClosingTillCount() },
                onPreviousDenomination: { viewModel.selectPreviousClosingDenomination() },
                onNextDenomination: { viewModel.selectNextClosingDenomination() },
                onSubmit: { viewModel.submitClosingTill() },
                onNoCashToday: {},
                onCancel: { viewModel.cancelCloseTill() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .closingCreditOnly(let submitting):
            closingCreditOnlyContent(submitting: submitting)

        case .waitingCloseApproval(
            _,
            let secondsRemaining,
            let cashMode,
            let expectedCloseFloat,
            let countedCloseFloat,
            let closeVariance
        ):
            waitingCloseApprovalContent(
                secondsRemaining: secondsRemaining,
                cashMode: cashMode,
                expectedCloseFloat: expectedCloseFloat,
                countedCloseFloat: countedCloseFloat,
                closeVariance: closeVariance
            )
        }
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

    private func closingCreditOnlyContent(submitting: Bool) -> some View {
        VStack(spacing: 16) {
            Text("Close till")
                .font(.title2.bold())
                .foregroundStyle(PosColors.burgundy)
            Text(
                viewModel.closeSupervisorApprovalRequired
                    ? "Credit cards only shift. A supervisor must approve before this till closes and the next cashier can sign in."
                    : "Close this credit-only shift to free the register for the next cashier."
            )
                .font(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            if !viewModel.status.isEmpty && viewModel.status != "Ready" {
                Text(viewModel.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(
                submitting
                    ? "Submitting…"
                    : (viewModel.closeSupervisorApprovalRequired ? "Submit for approval" : "Close till")
            ) {
                viewModel.submitClosingCreditOnly()
            }
            .buttonStyle(PosPrimaryButtonStyle())
            .disabled(submitting)
            Button("Cancel") {
                viewModel.cancelCloseTill()
            }
            .font(.headline)
            .foregroundStyle(PosColors.burgundy)
            .disabled(submitting)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waitingCloseApprovalContent(
        secondsRemaining: Int?,
        cashMode: String?,
        expectedCloseFloat: Double?,
        countedCloseFloat: Double?,
        closeVariance: Double?
    ) -> some View {
        VStack(spacing: 16) {
            Text("Till close — waiting for supervisor")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let timer = TillApprovalSummaryLogic.approvalTimerText(secondsRemaining: secondsRemaining) {
                Text(timer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let summary = TillApprovalSummaryLogic.closingSummaryLine(
                cashMode: cashMode,
                counted: countedCloseFloat,
                expected: expectedCloseFloat,
                variance: closeVariance
            ) {
                Text(summary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: 480)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            ProgressView()
                .padding(.top, 8)

            if !viewModel.status.isEmpty {
                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel") {
                viewModel.cancelCloseTill()
            }
            .font(.headline)
            .foregroundStyle(PosColors.burgundy)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PosPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(red: 0 / 255, green: 109 / 255, blue: 119 / 255))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    PosRootView()
}
