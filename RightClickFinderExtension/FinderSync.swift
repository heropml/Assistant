import Cocoa
import FinderSync
import OSLog

private let finderLog = Logger(
    subsystem: "com.local.RightClickAssistant.FinderExtension",
    category: "menu"
)

private final class MenuActionContext: NSObject {
    let action: ConfiguredAction
    let urls: [URL]

    init(action: ConfiguredAction, urls: [URL]) {
        self.action = action
        self.urls = urls
    }
}

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        // Some macOS releases don't deliver contextual-menu callbacks when only
        // the filesystem root is registered. Keep the broad root and explicitly
        // register the locations where Finder browsing normally happens.
        controller.directoryURLs = Set([
            URL(fileURLWithPath: "/", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
        ])
    }

    override var toolbarItemName: String { "右键助手" }
    override var toolbarItemToolTip: String { "常用 Finder 操作" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "右键助手") ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer
                || menuKind == .toolbarItemMenu else {
            return nil
        }

        let isContainer = menuKind == .contextualMenuForContainer
        let urls = targetURLs(for: menuKind)
        let configuration = SharedPreferences.configuration()
        let applicable = configuration.actions.filter { $0.matches(urls: urls, isContainer: isContainer) }
        finderLog.info(
            "Building menu kind=\(menuKind.rawValue, privacy: .public) targets=\(urls.count, privacy: .public) applicable=\(applicable.count, privacy: .public)"
        )
        guard !applicable.isEmpty else { return nil }

        let favorites = configuration.showsFavoritesAtTopLevel
            ? Array(applicable.filter(\.isFavorite).prefix(6))
            : []
        let favoriteIDs = Set(favorites.map(\.id))
        let remaining = applicable.filter { !favoriteIDs.contains($0.id) }
        let root = NSMenu(title: "右键助手")

        for action in favorites {
            root.addItem(menuItem(for: action, urls: urls))
        }

        if !favorites.isEmpty && !remaining.isEmpty {
            root.addItem(.separator())
        }

        if !remaining.isEmpty {
            let assistantItem = NSMenuItem(title: "右键助手", action: nil, keyEquivalent: "")
            assistantItem.image = NSImage(
                systemSymbolName: "cursorarrow.click.2",
                accessibilityDescription: "右键助手"
            )
            let submenu = buildSubmenu(actions: remaining, groups: configuration.groups, urls: urls)
            root.addItem(assistantItem)
            root.setSubmenu(submenu, for: assistantItem)
        }
        return root
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuActionContext else { return }

        if context.action.kind == .builtIn {
            switch context.action.builtInOperation {
            case .copyPath:
                copy(context.urls.map(\.path).joined(separator: "\n"))
                return
            case .copyName:
                copy(context.urls.map(\.lastPathComponent).joined(separator: "\n"))
                return
            case .cut, .paste, nil:
                break
            }
        }

        guard let url = SharedPreferences.executionURL(actionID: context.action.id, urls: context.urls),
              NSWorkspace.shared.open(url) else {
            Self.showError("无法执行动作", detail: "右键助手主程序未安装或无法启动。")
            return
        }
    }

    private func buildSubmenu(
        actions: [ConfiguredAction],
        groups: [ActionGroup],
        urls: [URL]
    ) -> NSMenu {
        let submenu = NSMenu(title: "右键助手")
        let groupedIDs = Set(groups.map(\.id))
        let ungrouped = actions.filter { action in
            guard let groupID = action.groupID else { return true }
            return !groupedIDs.contains(groupID)
        }

        for action in ungrouped {
            submenu.addItem(menuItem(for: action, urls: urls))
        }

        if !ungrouped.isEmpty && groups.contains(where: { group in actions.contains { $0.groupID == group.id } }) {
            submenu.addItem(.separator())
        }

        for group in groups {
            let groupActions = actions.filter { $0.groupID == group.id }
            guard !groupActions.isEmpty else { continue }
            let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            groupItem.image = NSImage(systemSymbolName: group.symbolName, accessibilityDescription: group.title)
            groupItem.isEnabled = false
            submenu.addItem(groupItem)
            for action in groupActions {
                submenu.addItem(menuItem(for: action, urls: urls))
            }
        }
        return submenu
    }

    private func menuItem(for action: ConfiguredAction, urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = MenuActionContext(action: action, urls: urls)
        if (action.kind == .application || action.kind == .terminal),
           let applicationURL = action.installedApplicationURL() {
            item.image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title)
                ?? NSImage(systemSymbolName: action.kind.symbolName, accessibilityDescription: action.title)
        }
        return item
    }

    private func targetURLs(for menuKind: FIMenuKind) -> [URL] {
        if menuKind == .contextualMenuForContainer {
            return controller.targetedURL().map { [$0] } ?? []
        }
        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        if let targeted = controller.targetedURL() {
            return [targeted]
        }
        return []
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func showError(_ message: String, detail: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = detail
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
