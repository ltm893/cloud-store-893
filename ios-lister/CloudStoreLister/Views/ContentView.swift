import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: InventoryLookupViewModel
    let signedInUser: String
    let onSignOut: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LookupInputView()
            }
            .listerAccountToolbar(user: signedInUser, onSignOut: onSignOut)
            .tabItem {
                Label("Input", systemImage: "keyboard")
            }
            .tag(0)

            NavigationStack {
                LookupResultsView()
            }
            .listerAccountToolbar(user: signedInUser, onSignOut: onSignOut)
            .tabItem {
                Label("Results", systemImage: "magnifyingglass")
            }
            .tag(1)

            NavigationStack {
                ListsView()
            }
            .listerAccountToolbar(user: signedInUser, onSignOut: onSignOut)
            .tabItem {
                Label("Lists", systemImage: "list.bullet")
            }
            .tag(2)
        }
        .tint(Color.listerAccent)
        .environmentObject(viewModel)
        .environment(\.selectedTab, $selectedTab)
    }
}

private extension View {
    func listerAccountToolbar(user: String, onSignOut: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Text(user)
                    Button("Sign out", role: .destructive, action: onSignOut)
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
    }
}

private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var selectedTab: Binding<Int> {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}

#if DEBUG
#Preview {
    ContentView(
        viewModel: InventoryLookupViewModel(),
        signedInUser: "preview@example.com",
        onSignOut: {}
    )
}
#endif
