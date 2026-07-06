import SwiftUI

struct RootView: View {
    @ObservedObject var auth: ListerAuthViewModel

    var body: some View {
        Group {
            switch auth.authGate {
            case .checking:
                ProgressView(auth.status)
            case .signIn:
                SignInView(hostLabel: AppConfig.apiHostLabel, onSignIn: auth.openOidcSignIn)
            case .oidcSignIn:
                OidcSignInScreen(
                    loginURL: auth.oidcLoginURL,
                    apiBaseURL: AppConfig.apiBaseURL,
                    onComplete: auth.onOidcWebViewComplete,
                    onCancel: auth.cancelOidcSignIn
                )
            case .signedIn(let user):
                if let lookupViewModel = auth.lookupViewModel {
                    ContentView(viewModel: lookupViewModel, signedInUser: user, onSignOut: auth.signOut)
                } else {
                    ProgressView("Loading…")
                }
            }
        }
        .tint(Color.listerAccent)
    }
}
