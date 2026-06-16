import Foundation
import Observation

enum CashierAuthGate: Equatable {
    case checking
    case signIn(pinAllowed: Bool, idpEnabled: Bool)
    case oidcSignIn
    case signedIn(user: String)
    case waitingApproval(
        email: String?,
        secondsRemaining: Int?,
        cashMode: String?,
        expectedOpeningFloat: Double?,
        openingCountedFloat: Double?,
        openingVariance: Double?
    )
    case openingTill(
        expectedOpeningFloat: Double?,
        denominations: [TillDenomination],
        counts: [String: String],
        selectedDenominationId: String?,
        submitting: Bool
    )
    case closingTill(
        expectedCloseFloat: Double?,
        openingCountedFloat: Double?,
        cashSalesTotal: Double?,
        changeGivenTotal: Double?,
        denominations: [TillDenomination],
        counts: [String: String],
        selectedDenominationId: String?,
        submitting: Bool
    )
    case closingCreditOnly(submitting: Bool)
    case waitingCloseApproval(
        closeToken: String?,
        secondsRemaining: Int?,
        cashMode: String?,
        expectedCloseFloat: Double?,
        countedCloseFloat: Double?,
        closeVariance: Double?
    )
}

@Observable
@MainActor
final class PosSessionViewModel {
    private static let approvalPollNanos: UInt64 = 2_500_000_000

    private(set) var authGate: CashierAuthGate = .checking
    private(set) var status = "Checking session…"
    private(set) var lastSession: CashierSessionResponse?
    private(set) var signedInViaTillResume = false

    private let api: PosAPIClient
    private let cookieStore: CookieStore
    private let apiBaseURL: URL
    private let registerId: String
    private var requireFreshIdpLogin = false
    private var approvalPollTask: Task<Void, Never>?
    private var closePollTask: Task<Void, Never>?

    var activeTillId: Int? { lastSession?.tillId }
    var activePosSessionId: Int? { lastSession?.posSessionId }

    init(
        apiBaseURL: URL = AppConfig.apiBaseURL,
        registerId: String = AppConfig.registerId,
        cookieStore: CookieStore = CookieStore()
    ) {
        self.apiBaseURL = apiBaseURL
        self.registerId = registerId
        self.cookieStore = cookieStore
        self.api = PosAPIClient(baseURL: apiBaseURL, cookieStore: cookieStore)
    }

    var oidcLoginURL: URL {
        AppConfigLogic.oidcLoginURL(
            base: apiBaseURL,
            registerId: registerId,
            freshLogin: requireFreshIdpLogin
        )
    }

    func makeRegisterViewModel() -> PosRegisterViewModel {
        let creditOnly = lastSession?.cashMode == "credit_only"
            || lastSession?.cashEnabled == false
        return PosRegisterViewModel(
            api: api,
            cashEnabled: lastSession?.cashEnabled ?? true,
            creditOnlyPayments: creditOnly
        )
    }

    func probeSessionOnLaunch() {
        Task { await probeSession() }
    }

    func openOidcSignIn() {
        stopApprovalPoll()
        authGate = .oidcSignIn
        status = "Signing in…"
    }

    func cancelOidcSignIn() {
        let pinAllowed = lastSession.map { $0.pinAllowed && !$0.supervisorApprovalRequired } ?? false
        let idpEnabled = lastSession?.idpEnabled ?? true
        authGate = .signIn(pinAllowed: pinAllowed, idpEnabled: idpEnabled)
        status = "Ready"
    }

    func onOidcWebViewComplete(completionURL: URL) {
        stopApprovalPoll()
        status = "Completing sign-in…"
        authGate = .checking
        signedInViaTillResume = OidcRedirectLogic.isResumeRedirect(completionURL: completionURL)

        if let token = OidcRedirectLogic.parsePendingRequestToken(from: completionURL) {
            cookieStore.rememberPendingRequestToken(token, baseURL: apiBaseURL)
        }

        Task {
            await syncWebViewCookiesWithRetry()
            if let token = OidcRedirectLogic.parsePendingRequestToken(from: completionURL) {
                cookieStore.rememberPendingRequestToken(token, baseURL: apiBaseURL)
            }
            if OidcRedirectLogic.isAwaitingTillRedirect(completionURL: completionURL) {
                cookieStore.pinAwaitingTillFromStoreIfNeeded(baseURL: apiBaseURL)
            }
            await probeSession()
            ensureWaitingApprovalAfterOidc(completionURL: completionURL)
        }
    }

    func recheckSession() {
        Task { await probeSession() }
    }

    func cancelApprovalWait() {
        Task {
            status = "Cancelling…"
            try? await api.cancelApproval()
            await returnToFreshSignIn(status: "Login request cancelled")
            await probeSession(showChecking: false)
            if case .signIn = authGate {
                status = "Login request cancelled"
            }
        }
    }

    func signOutForBreak() {
        Task {
            stopApprovalPoll()
            stopClosePoll()
            status = "Signing out…"
            try? await api.logoutCashier()
            await WebViewCookieSync.clearIdpCookies()
            requireFreshIdpLogin = true
            lastSession = nil
            signedInViaTillResume = false
            authGate = .signIn(pinAllowed: false, idpEnabled: true)
            status = "Signed out for break — till stays open"
            await probeSession(showChecking: false)
            if case .signIn = authGate {
                status = "Signed out for break — sign in to resume till"
            }
        }
    }

    func selectTillDenomination(_ denominationId: String) {
        updateOpeningTillGate { gate in
            gate.copy(selectedDenominationId: denominationId)
        }
    }

    func appendTillDigit(_ digit: Character) {
        guard case .openingTill(_, _, let counts, let selectedDenominationId, _) = authGate,
              let id = selectedDenominationId else { return }
        let current = counts[id] ?? ""
        guard current.count < 4 else { return }
        let next = current == "0" ? String(digit) : current + String(digit)
        updateTillCount(denominationId: id, value: next)
    }

    func clearTillCount() {
        guard case .openingTill(_, _, _, let selectedDenominationId, _) = authGate,
              let id = selectedDenominationId else { return }
        updateTillCount(denominationId: id, value: "")
    }

    func backspaceTillCount() {
        guard case .openingTill(_, _, let counts, let selectedDenominationId, _) = authGate,
              let id = selectedDenominationId else { return }
        let next = String((counts[id] ?? "").dropLast())
        updateTillCount(denominationId: id, value: next)
    }

    func selectNextTillDenomination() {
        updateOpeningTillGate { gate in
            guard !gate.denominations.isEmpty else { return gate }
            let currentIdx = gate.denominations.firstIndex { $0.id == gate.selectedDenominationId } ?? -1
            let nextIdx = currentIdx < 0 ? 0 : (currentIdx + 1) % gate.denominations.count
            return gate.copy(selectedDenominationId: gate.denominations[nextIdx].id)
        }
    }

    func selectPreviousTillDenomination() {
        updateOpeningTillGate { gate in
            guard !gate.denominations.isEmpty else { return gate }
            let currentIdx = gate.denominations.firstIndex { $0.id == gate.selectedDenominationId } ?? 0
            let prevIdx = currentIdx <= 0 ? gate.denominations.count - 1 : currentIdx - 1
            return gate.copy(selectedDenominationId: gate.denominations[prevIdx].id)
        }
    }

    func submitOpeningTill() {
        guard case .openingTill(let expected, let denominations, let counts, _, _) = authGate else { return }
        let nonEmptyCounts = counts.compactMap { id, raw -> (String, Int)? in
            let count = Int(raw) ?? 0
            return count > 0 ? (id, count) : nil
        }
        let countedTotal = TillCountLogic.sumTillCounts(denominations: denominations, counts: counts)
        submitTillRequest(
            cashMode: "cash_and_credit",
            denominations: Dictionary(uniqueKeysWithValues: nonEmptyCounts),
            countedTotal: countedTotal,
            expectedOpeningFloat: expected,
            denominationsForSummary: denominations,
            countsForSummary: counts
        )
    }

    func submitNoCashToday() {
        submitTillRequest(cashMode: "credit_only")
    }

    func cancelOpeningTill() {
        Task {
            status = "Cancelling…"
            try? await api.cancelOpeningTill()
            await returnToFreshSignIn(status: "Sign-in cancelled")
            await probeSession(showChecking: false)
            if case .signIn = authGate {
                status = "Sign-in cancelled"
            }
        }
    }

    func beginCloseTill() {
        Task {
            status = "Loading close till…"
            do {
                let preview = try await api.closeTillPreview()
                guard preview.ok else {
                    status = preview.error ?? "Cannot close till"
                    return
                }
                if preview.cartBlocked {
                    status = "Clear the cart before closing the till"
                    return
                }
                if preview.creditOnly {
                    enterClosingCreditOnly()
                } else {
                    enterClosingTill(preview)
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func cancelCloseTill() {
        Task {
            stopClosePoll()
            try? await api.cancelCloseTill()
            let user = lastSession?.displayUser ?? "Cashier"
            authGate = .signedIn(user: user)
            status = "Close till cancelled"
        }
    }

    func submitClosingCreditOnly() {
        submitCloseTillRequest(cashMode: "credit_only")
    }

    func submitClosingTill() {
        guard case .closingTill(_, _, _, _, let denominations, let counts, _, _) = authGate else { return }
        let nonEmptyCounts = counts.compactMap { id, raw -> (String, Int)? in
            let count = Int(raw) ?? 0
            return count > 0 ? (id, count) : nil
        }
        let countedTotal = TillCountLogic.sumTillCounts(denominations: denominations, counts: counts)
        submitCloseTillRequest(
            cashMode: "cash_and_credit",
            denominations: Dictionary(uniqueKeysWithValues: nonEmptyCounts),
            countedTotal: countedTotal
        )
    }

    func selectClosingDenomination(_ denominationId: String) {
        updateClosingTillGate { $0.copy(selectedDenominationId: denominationId) }
    }

    func appendClosingTillDigit(_ digit: Character) {
        guard case .closingTill(_, _, _, _, _, let counts, let selectedDenominationId, _) = authGate,
              let id = selectedDenominationId else { return }
        let current = counts[id] ?? ""
        guard current.count < 4 else { return }
        let next = current == "0" ? String(digit) : current + String(digit)
        updateClosingTillCount(denominationId: id, value: next)
    }

    func clearClosingTillCount() {
        guard case .closingTill(_, _, _, _, _, _, let selectedDenominationId, _) = authGate,
              let id = selectedDenominationId else { return }
        updateClosingTillCount(denominationId: id, value: "")
    }

    func backspaceClosingTillCount() {
        guard case .closingTill(_, _, _, _, _, let counts, let selectedDenominationId, _) = authGate,
              let id = selectedDenominationId else { return }
        updateClosingTillCount(denominationId: id, value: String((counts[id] ?? "").dropLast()))
    }

    func selectNextClosingDenomination() {
        updateClosingTillGate { gate in
            guard !gate.denominations.isEmpty else { return gate }
            let currentIdx = gate.denominations.firstIndex { $0.id == gate.selectedDenominationId } ?? -1
            let nextIdx = currentIdx < 0 ? 0 : (currentIdx + 1) % gate.denominations.count
            return gate.copy(selectedDenominationId: gate.denominations[nextIdx].id)
        }
    }

    func selectPreviousClosingDenomination() {
        updateClosingTillGate { gate in
            guard !gate.denominations.isEmpty else { return gate }
            let currentIdx = gate.denominations.firstIndex { $0.id == gate.selectedDenominationId } ?? 0
            let prevIdx = currentIdx <= 0 ? gate.denominations.count - 1 : currentIdx - 1
            return gate.copy(selectedDenominationId: gate.denominations[prevIdx].id)
        }
    }

    private func syncWebViewCookiesWithRetry() async {
        await WebViewCookieSync.sync(baseURL: apiBaseURL, cookieStore: cookieStore)
        try? await Task.sleep(nanoseconds: 150_000_000)
        await WebViewCookieSync.sync(baseURL: apiBaseURL, cookieStore: cookieStore)
        cookieStore.pinAwaitingTillFromStoreIfNeeded(baseURL: apiBaseURL)
    }

    private func ensureOpeningTillCookies() async {
        await syncWebViewCookiesWithRetry()
    }

    private func ensureWaitingApprovalAfterOidc(completionURL: URL) {
        guard case .signIn = authGate else { return }
        let hasPendingURL = OidcRedirectLogic.parsePendingRequestToken(from: completionURL) != nil
            || completionURL.absoluteString.contains("approval=pending")
        guard hasPendingURL || cookieStore.hasPinnedPendingToken else { return }

        let approval = lastSession?.approval
        authGate = .waitingApproval(
            email: approval?.cashierEmail,
            secondsRemaining: approval?.secondsRemaining,
            cashMode: approval?.cashMode,
            expectedOpeningFloat: approval?.expectedOpeningFloat,
            openingCountedFloat: approval?.openingCountedFloat,
            openingVariance: approval?.openingVariance
        )
        status = "Waiting for supervisor approval"
        startApprovalPoll()
    }

    private func probeSession(showChecking: Bool = true) async {
        if showChecking {
            authGate = .checking
            status = "Checking session…"
        }

        do {
            let session = try await api.fetchCashierSession()
            lastSession = session
            applySessionProbe(session)
        } catch {
            lastSession = nil
            stopApprovalPoll()
            authGate = .signIn(pinAllowed: false, idpEnabled: true)
            status = "Cannot reach server — \(error.localizedDescription)"
        }
    }

    private func applySessionProbe(_ session: CashierSessionResponse) {
        if session.awaitingTill {
            stopApprovalPoll()
            Task { await loadOpeningTillGate() }
            return
        }

        if session.ok {
            stopApprovalPoll()
            requireFreshIdpLogin = false
            let user = session.displayUser ?? "Cashier"
            authGate = .signedIn(user: user)
            if signedInViaTillResume {
                status = "Resumed active till"
            } else if session.tillId != nil {
                status = "Signed in — till open"
            } else {
                status = "Signed in"
            }
            return
        }

        signedInViaTillResume = false

        if session.pending {
            authGate = waitingApprovalGate(from: session)
            status = "Waiting for supervisor approval"
            startApprovalPoll()
            return
        }

        stopApprovalPoll()
        let pinAllowed = session.pinAllowed && !session.supervisorApprovalRequired
        authGate = .signIn(pinAllowed: pinAllowed, idpEnabled: session.idpEnabled)
        status = session.supervisorApprovalRequired
            ? "Sign in with Oracle"
            : "Ready"
    }

    private func waitingApprovalGate(from session: CashierSessionResponse) -> CashierAuthGate {
        let approval = session.approval
        return .waitingApproval(
            email: approval?.cashierEmail,
            secondsRemaining: approval?.secondsRemaining,
            cashMode: approval?.cashMode,
            expectedOpeningFloat: approval?.expectedOpeningFloat,
            openingCountedFloat: approval?.openingCountedFloat,
            openingVariance: approval?.openingVariance
        )
    }

    private func waitingApprovalGate(
        email: String?,
        secondsRemaining: Int?,
        from status: ApprovalStatusResponse
    ) -> CashierAuthGate {
        .waitingApproval(
            email: email ?? status.displayEmail,
            secondsRemaining: secondsRemaining ?? status.secondsRemaining,
            cashMode: status.cashMode,
            expectedOpeningFloat: status.expectedOpeningFloat,
            openingCountedFloat: status.openingCountedFloat,
            openingVariance: status.openingVariance
        )
    }

    private func startApprovalPoll() {
        approvalPollTask?.cancel()
        approvalPollTask = Task {
            await pollApprovalOnce()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.approvalPollNanos)
                guard !Task.isCancelled else { break }
                await pollApprovalOnce()
            }
        }
    }

    private func stopApprovalPoll() {
        approvalPollTask?.cancel()
        approvalPollTask = nil
    }

    private func pollApprovalOnce() async {
        guard case .waitingApproval(let email, let secondsRemaining, _, _, _, _) = authGate else {
            return
        }

        do {
            let poll = try await api.pollApprovalStatus()
            switch poll.status.lowercased() {
            case "approved":
                if poll.ok {
                    finishApprovedLogin()
                }
            case "pending":
                authGate = waitingApprovalGate(
                    email: email,
                    secondsRemaining: secondsRemaining,
                    from: poll
                )
                status = "Waiting for supervisor approval"
            case "denied", "expired", "cancelled":
                stopApprovalPoll()
                if let host = apiBaseURL.host {
                    cookieStore.clearHost(host)
                }
                let message: String
                switch poll.status.lowercased() {
                case "denied":
                    message = poll.reason ?? "Supervisor denied login"
                case "expired":
                    message = "Login request expired — sign in again"
                default:
                    message = "Login request cancelled"
                }
                authGate = .signIn(
                    pinAllowed: false,
                    idpEnabled: lastSession?.idpEnabled ?? true
                )
                status = message
            default:
                if let error = poll.error {
                    status = error
                }
            }
        } catch let error as PosAPIError {
            switch error {
            case .httpStatus(401, _):
                stopApprovalPoll()
                authGate = .signIn(pinAllowed: false, idpEnabled: lastSession?.idpEnabled ?? true)
                status = "No pending login request — sign in again"
            default:
                status = "Waiting for supervisor approval — \(error.localizedDescription)"
            }
        } catch {
            status = "Waiting for supervisor approval — \(error.localizedDescription)"
        }
    }

    /// Finish login on a fresh task — do not cancel the poll job before session fetch runs (Android parity).
    private func finishApprovedLogin() {
        Task { @MainActor in
            await applyApprovedSession()
        }
        stopApprovalPoll()
    }

    private func applyApprovedSession() async {
        status = "Completing sign-in…"
        do {
            let session = try await api.fetchCashierSession()
            lastSession = session
            if session.ok {
                applySessionProbe(session)
            } else {
                authGate = .signIn(pinAllowed: false, idpEnabled: lastSession?.idpEnabled ?? true)
                status = "Approved but session did not persist — sign in again"
            }
        } catch is CancellationError {
            return
        } catch {
            authGate = .signIn(pinAllowed: false, idpEnabled: lastSession?.idpEnabled ?? true)
            status = error.localizedDescription
        }
    }

    private func loadOpeningTillGate() async {
        authGate = .checking
        status = "Loading till config…"
        do {
            let config = try await api.fetchTillConfig()
            enterOpeningTill(config)
        } catch {
            clearCashierCookies()
            authGate = .signIn(pinAllowed: false, idpEnabled: lastSession?.idpEnabled ?? true)
            status = "Cannot load till config — \(error.localizedDescription)"
        }
    }

    private func enterOpeningTill(_ config: TillConfigResponse) {
        stopApprovalPoll()
        authGate = .openingTill(
            expectedOpeningFloat: config.expectedOpeningFloat,
            denominations: config.denominations,
            counts: [:],
            selectedDenominationId: config.denominations.first?.id,
            submitting: false
        )
        status = "Count opening till"
    }

    private func updateTillCount(denominationId: String, value: String) {
        updateOpeningTillGate { gate in
            var counts = gate.counts
            counts[denominationId] = value
            return gate.copy(counts: counts)
        }
    }

    private func updateOpeningTillGate(_ transform: (OpeningTillGate) -> OpeningTillGate) {
        guard case .openingTill(let expected, let denominations, let counts, let selected, let submitting) = authGate else {
            return
        }
        let gate = OpeningTillGate(
            expectedOpeningFloat: expected,
            denominations: denominations,
            counts: counts,
            selectedDenominationId: selected,
            submitting: submitting
        )
        let next = transform(gate)
        authGate = .openingTill(
            expectedOpeningFloat: next.expectedOpeningFloat,
            denominations: next.denominations,
            counts: next.counts,
            selectedDenominationId: next.selectedDenominationId,
            submitting: next.submitting
        )
    }

    private func submitTillRequest(
        cashMode: String,
        denominations: [String: Int]? = nil,
        countedTotal: Double? = nil,
        expectedOpeningFloat: Double? = nil,
        denominationsForSummary: [TillDenomination] = [],
        countsForSummary: [String: String] = [:]
    ) {
        Task {
            updateOpeningTillGate { $0.copy(submitting: true) }
            status = "Submitting till count…"

            do {
                await ensureOpeningTillCookies()

                let response = try await api.submitOpeningTill(
                    SubmitOpeningTillRequest(
                        cashMode: cashMode,
                        denominations: denominations,
                        countedTotal: countedTotal
                    )
                )

                if response.pending {
                    if let token = response.requestToken {
                        cookieStore.rememberPendingRequestToken(token, baseURL: apiBaseURL)
                    }
                    let counted = denominationsForSummary.isEmpty
                        ? nil
                        : TillCountLogic.sumTillCounts(
                            denominations: denominationsForSummary,
                            counts: countsForSummary
                        )
                    authGate = .waitingApproval(
                        email: nil,
                        secondsRemaining: nil,
                        cashMode: response.cashMode ?? cashMode,
                        expectedOpeningFloat: expectedOpeningFloat,
                        openingCountedFloat: counted,
                        openingVariance: response.openingVariance
                            ?? expectedOpeningFloat.flatMap { expected in
                                counted.map { $0 - expected }
                            }
                    )
                    status = "Waiting for supervisor approval"
                    startApprovalPoll()
                    return
                }

                if response.ok {
                    await applySessionAfterTillSubmit()
                    return
                }

                updateOpeningTillGate { $0.copy(submitting: false) }
                status = response.error ?? "Till submit failed"
            } catch let error as PosAPIError {
                switch error {
                case .httpStatus(401, _):
                    await returnToFreshSignIn(status: "Sign-in expired — sign in with Oracle again")
                case .httpStatus(409, let message):
                    await returnToFreshSignIn(status: registerInUseMessage(from: message))
                default:
                    updateOpeningTillGate { $0.copy(submitting: false) }
                    status = error.localizedDescription
                }
            } catch {
                updateOpeningTillGate { $0.copy(submitting: false) }
                status = error.localizedDescription
            }
        }
    }

    private func applySessionAfterTillSubmit() async {
        for attempt in 0 ..< 2 {
            do {
                let session = try await api.fetchCashierSession()
                lastSession = session
                applySessionProbe(session)
                if case .signedIn = authGate { return }
                if case .waitingApproval = authGate { return }
            } catch {
                if attempt == 1 {
                    await returnToFreshSignIn(
                        status: "Till submitted but session did not persist — sign in again"
                    )
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        await returnToFreshSignIn(status: "Till submitted but session did not persist — sign in again")
    }

    private func enterClosingCreditOnly() {
        stopClosePoll()
        authGate = .closingCreditOnly(submitting: false)
        status = "Close credit-only shift"
    }

    private func enterClosingTill(_ preview: CloseTillPreviewResponse) {
        stopClosePoll()
        authGate = .closingTill(
            expectedCloseFloat: preview.expectedCloseFloat,
            openingCountedFloat: preview.openingCountedFloat,
            cashSalesTotal: preview.cashSalesTotal,
            changeGivenTotal: preview.changeGivenTotal,
            denominations: preview.denominations,
            counts: [:],
            selectedDenominationId: preview.denominations.first?.id,
            submitting: false
        )
        status = "Count closing till"
    }

    private func submitCloseTillRequest(
        cashMode: String,
        denominations: [String: Int]? = nil,
        countedTotal: Double? = nil
    ) {
        Task {
            setCloseSubmitting(true)
            status = "Submitting close…"
            do {
                let response = try await api.submitCloseTill(
                    SubmitCloseTillRequest(
                        cashMode: cashMode,
                        denominations: denominations,
                        countedTotal: countedTotal
                    )
                )
                if response.approved {
                    await finishCloseTillSignedOff()
                    return
                }
                if response.pending {
                    authGate = .waitingCloseApproval(
                        closeToken: response.closeToken,
                        secondsRemaining: nil,
                        cashMode: response.cashMode,
                        expectedCloseFloat: response.expectedCloseFloat,
                        countedCloseFloat: response.countedCloseFloat,
                        closeVariance: response.closeVariance
                    )
                    status = "Waiting for supervisor to approve close"
                    startClosePoll()
                    return
                }
                setCloseSubmitting(false)
                status = response.error ?? "Close till failed"
            } catch {
                setCloseSubmitting(false)
                status = error.localizedDescription
            }
        }
    }

    private func setCloseSubmitting(_ submitting: Bool) {
        switch authGate {
        case .closingTill(let expected, let opening, let sales, let change, let denominations, let counts, let selected, _):
            authGate = .closingTill(
                expectedCloseFloat: expected,
                openingCountedFloat: opening,
                cashSalesTotal: sales,
                changeGivenTotal: change,
                denominations: denominations,
                counts: counts,
                selectedDenominationId: selected,
                submitting: submitting
            )
        case .closingCreditOnly:
            authGate = .closingCreditOnly(submitting: submitting)
        default:
            break
        }
    }

    private func finishCloseTillSignedOff() async {
        stopClosePoll()
        stopApprovalPoll()
        await WebViewCookieSync.clearIdpCookies()
        requireFreshIdpLogin = true
        lastSession = nil
        signedInViaTillResume = false
        clearCashierCookies()
        authGate = .checking
        status = "Till closed — sign in with your credentials"
        await probeSession(showChecking: false)
    }

    private func startClosePoll() {
        closePollTask?.cancel()
        closePollTask = Task {
            await pollCloseOnce()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.approvalPollNanos)
                guard !Task.isCancelled else { break }
                await pollCloseOnce()
            }
        }
    }

    private func stopClosePoll() {
        closePollTask?.cancel()
        closePollTask = nil
    }

    private func pollCloseOnce() async {
        guard case .waitingCloseApproval(let closeToken, _, _, _, _, _) = authGate else { return }
        do {
            let poll = try await api.closeTillStatus(closeToken: closeToken)
            switch poll.status?.lowercased() {
            case "approved":
                await finishCloseTillSignedOff()
            case "denied":
                stopClosePoll()
                let user = lastSession?.displayUser ?? "Cashier"
                authGate = .signedIn(user: user)
                status = poll.reason.map { "Close denied: \($0)" } ?? "Supervisor denied close"
            case "pending":
                authGate = .waitingCloseApproval(
                    closeToken: poll.closeToken ?? closeToken,
                    secondsRemaining: poll.secondsRemaining,
                    cashMode: poll.cashMode,
                    expectedCloseFloat: poll.expectedCloseFloat,
                    countedCloseFloat: poll.countedCloseFloat,
                    closeVariance: poll.closeVariance
                )
                status = "Waiting for supervisor to approve close"
            case "none":
                await handleAmbiguousClosePoll()
            default:
                if poll.ok {
                    await finishCloseTillSignedOff()
                }
            }
        } catch let error as PosAPIError {
            if case .httpStatus(401, _) = error {
                await finishCloseTillSignedOff()
            } else {
                status = "Waiting for supervisor to approve close — \(error.localizedDescription)"
            }
        } catch {
            status = "Waiting for supervisor to approve close — \(error.localizedDescription)"
        }
    }

    /// After supervisor approval the server may clear the session before the next poll sees `approved`.
    private func handleAmbiguousClosePoll() async {
        if let session = try? await api.fetchCashierSession(), session.ok {
            status = "Waiting for supervisor to approve close"
            return
        }
        await finishCloseTillSignedOff()
    }

    private func updateClosingTillCount(denominationId: String, value: String) {
        updateClosingTillGate { gate in
            var counts = gate.counts
            counts[denominationId] = value
            return gate.copy(counts: counts)
        }
    }

    private func updateClosingTillGate(_ transform: (ClosingTillGate) -> ClosingTillGate) {
        guard case .closingTill(
            let expected,
            let opening,
            let sales,
            let change,
            let denominations,
            let counts,
            let selected,
            let submitting
        ) = authGate else { return }
        let gate = ClosingTillGate(
            expectedCloseFloat: expected,
            openingCountedFloat: opening,
            cashSalesTotal: sales,
            changeGivenTotal: change,
            denominations: denominations,
            counts: counts,
            selectedDenominationId: selected,
            submitting: submitting
        )
        let next = transform(gate)
        authGate = .closingTill(
            expectedCloseFloat: next.expectedCloseFloat,
            openingCountedFloat: next.openingCountedFloat,
            cashSalesTotal: next.cashSalesTotal,
            changeGivenTotal: next.changeGivenTotal,
            denominations: next.denominations,
            counts: next.counts,
            selectedDenominationId: next.selectedDenominationId,
            submitting: next.submitting
        )
    }

    private func clearCashierCookies() {
        if let host = apiBaseURL.host {
            cookieStore.clearHost(host)
        } else {
            cookieStore.clearAll()
        }
    }

    /// Abandon in-progress sign-in / till open — next Oracle sign-in must ask for credentials.
    private func returnToFreshSignIn(status: String) async {
        stopApprovalPoll()
        stopClosePoll()
        await WebViewCookieSync.clearIdpCookies()
        requireFreshIdpLogin = true
        lastSession = nil
        signedInViaTillResume = false
        clearCashierCookies()
        authGate = .signIn(pinAllowed: false, idpEnabled: true)
        self.status = status
    }

    private func registerInUseMessage(from body: String?) -> String {
        guard let body, !body.isEmpty else {
            return "This tablet is in use — the current cashier must sign off first"
        }
        if let range = body.range(of: #""error"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let match = String(body[range])
            if let valueRange = match.range(of: #""([^"]+)""#, options: .regularExpression) {
                let quoted = String(match[valueRange])
                return quoted.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return "This tablet is in use — the current cashier must sign off first"
    }
}

private struct ClosingTillGate {
    let expectedCloseFloat: Double?
    let openingCountedFloat: Double?
    let cashSalesTotal: Double?
    let changeGivenTotal: Double?
    let denominations: [TillDenomination]
    let counts: [String: String]
    let selectedDenominationId: String?
    let submitting: Bool

    func copy(
        expectedCloseFloat: Double? = nil,
        openingCountedFloat: Double? = nil,
        cashSalesTotal: Double? = nil,
        changeGivenTotal: Double? = nil,
        denominations: [TillDenomination]? = nil,
        counts: [String: String]? = nil,
        selectedDenominationId: String?? = nil,
        submitting: Bool? = nil
    ) -> ClosingTillGate {
        ClosingTillGate(
            expectedCloseFloat: expectedCloseFloat ?? self.expectedCloseFloat,
            openingCountedFloat: openingCountedFloat ?? self.openingCountedFloat,
            cashSalesTotal: cashSalesTotal ?? self.cashSalesTotal,
            changeGivenTotal: changeGivenTotal ?? self.changeGivenTotal,
            denominations: denominations ?? self.denominations,
            counts: counts ?? self.counts,
            selectedDenominationId: selectedDenominationId ?? self.selectedDenominationId,
            submitting: submitting ?? self.submitting
        )
    }
}

private struct OpeningTillGate {
    let expectedOpeningFloat: Double?
    let denominations: [TillDenomination]
    let counts: [String: String]
    let selectedDenominationId: String?
    let submitting: Bool

    func copy(
        expectedOpeningFloat: Double? = nil,
        denominations: [TillDenomination]? = nil,
        counts: [String: String]? = nil,
        selectedDenominationId: String?? = nil,
        submitting: Bool? = nil
    ) -> OpeningTillGate {
        OpeningTillGate(
            expectedOpeningFloat: expectedOpeningFloat ?? self.expectedOpeningFloat,
            denominations: denominations ?? self.denominations,
            counts: counts ?? self.counts,
            selectedDenominationId: selectedDenominationId ?? self.selectedDenominationId,
            submitting: submitting ?? self.submitting
        )
    }
}
