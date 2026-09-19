import AppKit
import SwiftUI

@main
struct RightClickAssistantApp: App {
    @ObservedObject private var language = LanguageStore.shared
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store = ActionStore()
    @State private var isMenuBarExtraInserted = true

    var body: some Scene {
        WindowGroup(L10n.tr("右键助手"), id: "main") {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, language.locale)
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
                .environment(\.locale, language.locale)
                .onAppear { store.keepRunning() }
        }

        MenuBarExtra(isInserted: $isMenuBarExtraInserted) {
            AssistantMenuBarContent()
                .environmentObject(store)
                .environment(\.locale, language.locale)
        } label: {
            HStack(spacing: 4) {
                Label(L10n.tr("右键助手"), image: "AssistantMark")
                    .labelStyle(.iconOnly)
                if store.runningExecutionCount > 0 {
                    Text("\(store.runningExecutionCount)")
                }
            }
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentUserInterface()
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
    @ObservedObject private var language = LanguageStore.shared
    @EnvironmentObject private var store: ActionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !store.executions.isEmpty {
            Text(store.runningExecutionCount > 0 ? L10n.tr("正在执行 %@ 个动作", String(describing: store.runningExecutionCount)) : L10n.tr("最近执行"))
            ForEach(Array(store.executions.prefix(5))) { execution in
                Text(execution.summary)
            }
            Divider()
        }
        Button {
            showMainWindow()
        } label: {
            Label(L10n.tr("打开右键助手"), systemImage: "macwindow")
        }
        .keyboardShortcut("o")

        SettingsLink {
            Label(L10n.tr("扩展设置…"), systemImage: "gearshape")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label(L10n.tr("退出右键助手"), systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        store.keepRunning()
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        if let window = application.windows.first(where: { AppLanguage.allCases.map(\.appName).contains($0.title) }) {
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
