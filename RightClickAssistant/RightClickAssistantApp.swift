import SwiftUI

@main
struct RightClickAssistantApp: App {
    @StateObject private var store = ActionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 600)
                .onOpenURL { store.handleExecutionURL($0) }
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
