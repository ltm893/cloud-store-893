import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = InventoryLookupViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LookupInputView()
            }
            .tabItem {
                Label("Input", systemImage: "keyboard")
            }
            .tag(0)

            NavigationStack {
                LookupResultsView()
            }
            .tabItem {
                Label("Results", systemImage: "magnifyingglass")
            }
            .tag(1)

            NavigationStack {
                ListsView()
            }
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
    ContentView()
}
#endif
