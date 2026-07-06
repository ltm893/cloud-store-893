import SwiftUI

@main
struct CloudStoreListerApp: App {
    @StateObject private var auth = ListerAuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .onAppear { auth.probeSessionOnLaunch() }
        }
    }
}
