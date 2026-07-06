import Foundation

enum ListerAuthGate: Equatable {
    case checking
    case signIn
    case oidcSignIn
    case signedIn(user: String)
}

@MainActor
final class ListerAuthViewModel: ObservableObject {
    @Published private(set) var authGate: ListerAuthGate = .checking
    @Published private(set) var status = "Checking session…"
    @Published private(set) var lookupViewModel: InventoryLookupViewModel?

    let cookieStore = CookieStore()

    private let apiBaseURL: URL
    private let registerId: String
    private var api: ListerAPIClient
    private var requireFreshIdpLogin = false

    init(
        apiBaseURL: URL = AppConfig.apiBaseURL,
        registerId: String = AppConfig.registerId
    ) {
        self.apiBaseURL = apiBaseURL
        self.registerId = registerId
        self.api = ListerAPIClient(baseURL: apiBaseURL, cookieStore: cookieStore, registerId: registerId)
    }

    var oidcLoginURL: URL {
        AppConfigLogic.oidcLoginURL(
            base: apiBaseURL,
            registerId: registerId,
            freshLogin: requireFreshIdpLogin
        )
    }

    func probeSessionOnLaunch() {
        Task { await probeSession() }
    }

    func openOidcSignIn() {
        authGate = .oidcSignIn
        status = "Signing in…"
    }

    func cancelOidcSignIn() {
        authGate = .signIn
        status = "Ready"
    }

    func onOidcWebViewComplete(completionURL: URL) {
        authGate = .checking
        status = "Completing sign-in…"
        Task {
            await WebViewCookieSync.sync(baseURL: apiBaseURL, cookieStore: cookieStore)
            await probeSession()
        }
    }

    func signOut() {
        Task {
            try? await api.logoutCashier()
            lookupViewModel = nil
            authGate = .signIn
            status = "Signed out"
        }
    }

    private func probeSession() async {
        do {
            let session = try await api.fetchCashierSession()
            if session.ok, let user = session.displayUser {
                activateSignedIn(user: user)
                return
            }
            if session.idpEnabled {
                authGate = .signIn
                status = "Sign in required"
            } else {
                activateSignedIn(user: "Lister")
            }
        } catch {
            authGate = .signIn
            status = error.localizedDescription
        }
    }

    private func activateSignedIn(user: String) {
        lookupViewModel = InventoryLookupViewModel(
            api: InventoryAPIClient(baseURL: apiBaseURL, cookieStore: cookieStore)
        )
        authGate = .signedIn(user: user)
        status = user
        requireFreshIdpLogin = false
    }
}
