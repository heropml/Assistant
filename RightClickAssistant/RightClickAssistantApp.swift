import SwiftUI

@main
struct RightClickAssistantApp: App {
    @StateObject private var store = ActionStore()
    @State private var isMenuBarExtraInserted = true

    var body: some Scene {
        WindowGroup("右键助手", id: "main") {
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

        MenuBarExtra(isInserted: $isMenuBarExtraInserted) {
            AssistantMenuBarContent()
        } label: {
            Label("右键助手", image: "AssistantMark")
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct AssistantMenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            showMainWindow()
        } label: {
            Label("打开右键助手", systemImage: "macwindow")
        }
        .keyboardShortcut("o")

        SettingsLink {
            Label("扩展设置…", systemImage: "gearshape")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("退出右键助手", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        let application = NSApplication.shared
        if let window = application.windows.first(where: { $0.title == "右键助手" }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        application.activate(ignoringOtherApps: true)
    }
}
