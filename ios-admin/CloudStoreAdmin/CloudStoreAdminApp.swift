import SwiftUI

@main
struct CloudStoreAdminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AdminRootView()
        }
    }
}
