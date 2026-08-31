import Cocoa
import FinderSync

private enum MenuAction {
    case builtIn(QuickAction)
    case application(ApplicationAction)
}

private final class MenuActionContext: NSObject {
    let action: MenuAction
    let urls: [URL]

    init(action: MenuAction, urls: [URL]) {
        self.action = action
        self.urls = urls
    }
}

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        controller.directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override var toolbarItemName: String { "右键助手" }
    override var toolbarItemToolTip: String { "常用 Finder 操作" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "右键助手") ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        let builtInActions = SharedPreferences.enabledActions()
        let applicationActions = SharedPreferences.applicationActions().filter(\.isEnabled)
        guard !builtInActions.isEmpty || !applicationActions.isEmpty else { return nil }

        let root = NSMenu(title: "右键助手")
        let assistantItem = NSMenuItem(title: "右键助手", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "右键助手")
        let urls = targetURLs(for: menuKind)

        for action in builtInActions {
            let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuActionContext(action: .builtIn(action), urls: urls)
            item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title)
            submenu.addItem(item)
        }

        if !builtInActions.isEmpty && !applicationActions.isEmpty {
            submenu.addItem(.separator())
        }

        for application in applicationActions {
            let item = NSMenuItem(title: application.menuTitle, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuActionContext(action: .application(application), urls: urls)
            if let applicationURL = application.installedApplicationURL() {
                item.image = NSWorkspace.shared.icon(forFile: applicationURL.path)
            }
            submenu.addItem(item)
        }

        root.addItem(assistantItem)
        root.setSubmenu(submenu, for: assistantItem)
        return root
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuActionContext else { return }

        switch context.action {
        case .builtIn(.copyPath):
            copy(context.urls.map(\.path).joined(separator: "\n"))
        case .builtIn(.copyName):
            copy(context.urls.map(\.lastPathComponent).joined(separator: "\n"))
        case .builtIn(.newTextFile):
            createTextFile(in: workingDirectory(for: context.urls.first))
        case .builtIn(.openInTerminal):
            openTerminal(at: workingDirectory(for: context.urls.first))
        case let .application(application):
            open(context.urls, with: application)
        }
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

    private func workingDirectory(for url: URL?) -> URL {
        guard let url else { return FileManager.default.homeDirectoryForCurrentUser }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func createTextFile(in directory: URL) {
        let manager = FileManager.default
        var candidate = directory.appendingPathComponent("未命名文稿.txt")
        var index = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("未命名文稿 \(index).txt")
            index += 1
        }

        do {
            try Data().write(to: candidate, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([candidate])
        } catch {
            Self.showError("无法新建文本文件", detail: error.localizedDescription)
        }
    }

    private func open(_ urls: [URL], with application: ApplicationAction) {
        guard !urls.isEmpty else { return }
        guard let applicationURL = application.installedApplicationURL() else {
            Self.showError("未找到\(application.applicationName)", detail: "应用可能已移动或删除，请在右键助手中重新添加。")
            return
        }

        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                FinderSync.showError("无法使用\(application.applicationName)打开", detail: error.localizedDescription)
            }
        }
    }

    private func openTerminal(at directory: URL) {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                FinderSync.showError("无法打开终端", detail: error.localizedDescription)
            }
        }
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
