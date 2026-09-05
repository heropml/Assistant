import AppKit
import SwiftUI

@main
struct RightClickAssistantApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store = ActionStore()
    @State private var isMenuBarExtraInserted = true

    var body: some Scene {
        WindowGroup("右键助手", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 600)
                .onOpenURL {
                    store.handleExecutionURL(
                        $0,
                        terminateAfterExecution: applicationDelegate.beginExecution()
                    )
                }
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

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var initialLaunchResolved = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            initialLaunchResolved = true
            presentUserInterface()
            return
        }

        // File/URL launches are delivered after didFinishLaunching. Keep the
        // process UI-less while waiting, but recover normally if macOS started
        // us for another non-default reason such as state restoration.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.initialLaunchResolved else { return }
            self.initialLaunchResolved = true
            self.presentUserInterface()
        }
    }

    func beginExecution() -> Bool {
        guard !initialLaunchResolved else { return false }
        initialLaunchResolved = true
        return true
    }

    private func presentUserInterface() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
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
