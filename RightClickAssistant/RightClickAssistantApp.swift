import SwiftUI

@main
struct RightClickAssistantApp: App {
    @StateObject private var store = ActionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 500)
        }
        .defaultSize(width: 780, height: 560)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
