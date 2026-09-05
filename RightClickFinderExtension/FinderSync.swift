import Cocoa
import Darwin
import FinderSync
import OSLog

private let finderLog = Logger(
    subsystem: "com.local.RightClickAssistant.FinderExtension",
    category: "menu"
)

private struct MenuActionContext {
    let action: ConfiguredAction
    let urls: [URL]
    let isContainer: Bool

    init(action: ConfiguredAction, urls: [URL], isContainer: Bool) {
        self.action = action
        self.urls = urls
        self.isContainer = isContainer
    }
}

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private var menuActionContexts: [Int: MenuActionContext] = [:]
    private var nextMenuActionTag = 1

    override init() {
        super.init()
        // App Sandbox redirects Foundation's "current home" to the extension
        // container. Finder reports the real POSIX home, so register that path
        // explicitly or Desktop/Documents contextual-menu callbacks never fire.
        var monitoredURLs = Set([
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared", isDirectory: true),
        ])
        if let realHomeDirectoryURL = Self.realHomeDirectoryURL() {
            monitoredURLs.insert(realHomeDirectoryURL)
            for relativePath in [
                "Desktop",
                "Documents",
                "Downloads",
                "Movies",
                "Music",
                "Pictures",
                "Public",
                "Library/Mobile Documents/com~apple~CloudDocs",
            ] {
                monitoredURLs.insert(
                    realHomeDirectoryURL
                        .appendingPathComponent(relativePath, isDirectory: true)
                        .standardizedFileURL
                )
            }
        } else {
            finderLog.error("Unable to determine the real POSIX home directory")
        }
        controller.directoryURLs = monitoredURLs
        finderLog.info("Monitoring \(monitoredURLs.count, privacy: .public) directories")
    }

    private static func realHomeDirectoryURL() -> URL? {
        guard let passwordEntry = getpwuid(getuid()),
              let homePath = passwordEntry.pointee.pw_dir else {
            return nil
        }
        let path = String(cString: homePath)
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    override var toolbarItemName: String { "右键助手" }
    override var toolbarItemToolTip: String { "常用 Finder 操作" }
    override var toolbarItemImage: NSImage {
        brandImage(pointSize: 20)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer
                || menuKind == .contextualMenuForSidebar
                || menuKind == .toolbarItemMenu else {
            return nil
        }

        // Finder recreates menu items across its extension boundary. Keep the
        // action payload in this principal object and send only the integer tag.
        menuActionContexts.removeAll(keepingCapacity: true)

        let context = targetContext(for: menuKind)
        let urls = context.urls
        let isContainer = context.isContainer
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
            root.addItem(menuItem(for: action, urls: urls, isContainer: isContainer))
        }

        if !favorites.isEmpty && !remaining.isEmpty {
            root.addItem(.separator())
        }

        if !remaining.isEmpty {
            let assistantItem = NSMenuItem(title: "右键助手", action: nil, keyEquivalent: "")
            assistantItem.image = brandImage(pointSize: 16)
            let submenu = buildSubmenu(
                actions: remaining,
                groups: configuration.groups,
                urls: urls,
                isContainer: isContainer
            )
            root.addItem(assistantItem)
            root.setSubmenu(submenu, for: assistantItem)
        }
        return root
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        finderLog.info(
            "Performing menu action tag=\(sender.tag, privacy: .public) title=\(sender.title, privacy: .public)"
        )
        guard let context = menuActionContexts[sender.tag] else {
            finderLog.error("Missing action context for menu tag \(sender.tag, privacy: .public)")
            return
        }

        guard let url = SharedPreferences.executionURL(
            actionID: context.action.id,
            urls: context.urls,
            isContainer: context.isContainer
        ) else {
            Self.showError("无法执行动作", detail: "右键助手主程序未安装或无法启动。")
            return
        }
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = false
        openConfiguration.hides = false
        openConfiguration.addsToRecentItems = false
        openConfiguration.allowsRunningApplicationSubstitution = false

        let applicationURL = Bundle(for: FinderSync.self).bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard applicationURL.pathExtension == "app" else {
            SharedPreferences.discardExecutionRequest(from: url)
            Self.showError("无法执行动作", detail: "无法定位右键助手主程序。")
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: openConfiguration
        ) { application, error in
            guard error == nil, application != nil else {
                SharedPreferences.discardExecutionRequest(from: url)
                Self.showError("无法执行动作", detail: "右键助手主程序未安装或无法启动。")
                return
            }
        }
    }

    private func buildSubmenu(
        actions: [ConfiguredAction],
        groups: [ActionGroup],
        urls: [URL],
        isContainer: Bool
    ) -> NSMenu {
        let submenu = NSMenu(title: "右键助手")
        var hasRenderedSection = false

        for group in groups {
            let groupActions = actions.filter { $0.groupID == group.id }
            guard !groupActions.isEmpty else { continue }
            if hasRenderedSection {
                submenu.addItem(.separator())
            }
            let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            groupItem.image = cyberSymbolImage(
                named: group.symbolName,
                fallbackName: "folder.fill",
                description: group.title
            )
            groupItem.isEnabled = false
            submenu.addItem(groupItem)
            for action in groupActions {
                submenu.addItem(menuItem(for: action, urls: urls, isContainer: isContainer))
            }
            hasRenderedSection = true
        }

        let ungroupedActions = actions.filter { $0.groupID == nil }
        if !ungroupedActions.isEmpty {
            if hasRenderedSection {
                submenu.addItem(.separator())
            }
            for action in ungroupedActions {
                submenu.addItem(menuItem(for: action, urls: urls, isContainer: isContainer))
            }
        }
        return submenu
    }

    private func menuItem(for action: ConfiguredAction, urls: [URL], isContainer: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
        // Finder owns the menu UI, but actions must be delivered back to this
        // extension instance. Without an explicit target Finder only dismisses
        // the menu and never enters the selector.
        item.target = self
        let tag = nextMenuActionTag
        nextMenuActionTag += 1
        menuActionContexts[tag] = MenuActionContext(action: action, urls: urls, isContainer: isContainer)
        item.tag = tag
        item.image = menuImage(for: action)
        return item
    }

    private func menuImage(for action: ConfiguredAction) -> NSImage? {
        let configuredName = action.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let assetName = bundledDefaultActionImageName(for: action, configuredName: configuredName),
           let image = bundledActionImage(named: assetName, description: action.title) {
            return image
        }

        let usesDefaultSymbol = configuredName.isEmpty || configuredName == action.kind.symbolName
        if usesDefaultSymbol,
           (action.kind == .application || action.kind == .terminal),
           let applicationURL = action.installedApplicationURL() {
            let source = NSWorkspace.shared.icon(forFile: applicationURL.path)
            let image = (source.copy() as? NSImage) ?? source
            image.size = NSSize(width: 16, height: 16)
            image.accessibilityDescription = action.title
            return image
        }

        let symbolName = configuredName.isEmpty ? action.kind.symbolName : configuredName
        return cyberSymbolImage(
            named: symbolName,
            fallbackName: action.kind.symbolName,
            description: action.title
        )
    }

    private func cyberSymbolImage(
        named name: String,
        fallbackName: String,
        description: String
    ) -> NSImage? {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: description)
                ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: description) else {
            return nil
        }
        let sizing = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let palette = NSImage.SymbolConfiguration(paletteColors: [
            NSColor(srgbRed: 0, green: 0.898, blue: 1, alpha: 1),
            NSColor(srgbRed: 1, green: 0.169, blue: 0.839, alpha: 1),
            NSColor(srgbRed: 0.482, green: 0.235, blue: 1, alpha: 1),
        ])
        let configured = source.withSymbolConfiguration(sizing.applying(palette)) ?? source
        let image = (configured.copy() as? NSImage) ?? configured
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = false
        image.accessibilityDescription = description
        return image
    }

    private func bundledDefaultActionImageName(
        for action: ConfiguredAction,
        configuredName: String
    ) -> String? {
        switch (action.id, configuredName) {
        case ("builtin.copyPath", "point.topleft.down.to.point.bottomright.curvepath"):
            "ActionCopyPath"
        case ("template.text", "doc.badge.plus"):
            "ActionNewTextFile"
        case ("terminal.system", "apple.terminal"):
            "ActionTerminal"
        default:
            nil
        }
    }

    private func bundledActionImage(named name: String, description: String) -> NSImage? {
        guard !name.isEmpty,
              let source = Bundle(for: FinderSync.self).image(forResource: NSImage.Name(name)) else {
            return nil
        }
        let image = (source.copy() as? NSImage) ?? source
        image.size = NSSize(width: 16, height: 16)
        // Action artwork is intentionally multicolour. Marking it as a template makes
        // AppKit discard the cyan/magenta cyber palette and render a monochrome mask.
        image.isTemplate = false
        image.accessibilityDescription = description
        return image
    }

    private func brandImage(pointSize: CGFloat) -> NSImage {
        let assetName = NSImage.Name("AssistantMark")
        let source = Bundle(for: FinderSync.self).image(forResource: assetName)
            ?? NSImage(named: assetName)
            ?? NSImage(
                systemSymbolName: "cursorarrow.click.2",
                accessibilityDescription: "右键助手"
            )
            ?? NSImage()
        let image = (source.copy() as? NSImage) ?? source
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        image.accessibilityDescription = "右键助手"
        return image
    }

    private func targetContext(for menuKind: FIMenuKind) -> (urls: [URL], isContainer: Bool) {
        if menuKind == .contextualMenuForContainer {
            return (controller.targetedURL().map { [$0] } ?? [], true)
        }
        if menuKind == .contextualMenuForSidebar {
            return (controller.targetedURL().map { [$0] } ?? [], false)
        }
        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            return (selected, false)
        }
        if let targeted = controller.targetedURL() {
            return ([targeted], menuKind == .toolbarItemMenu)
        }
        return ([], menuKind == .toolbarItemMenu)
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
