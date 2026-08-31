import AppKit
import Foundation

enum QuickAction: String, CaseIterable, Codable, Identifiable {
    case copyPath
    case copyName
    case newTextFile
    case openInTerminal

    static let defaultEnabledActions: [QuickAction] = [
        .copyPath, .copyName, .newTextFile, .openInTerminal
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copyPath: "复制路径"
        case .copyName: "复制文件名"
        case .newTextFile: "新建文本文件"
        case .openInTerminal: "在终端打开"
        }
    }

    var detail: String {
        switch self {
        case .copyPath: "将所选项目的完整路径复制到剪贴板"
        case .copyName: "只复制所选项目的名称"
        case .newTextFile: "在当前位置创建一个空白 .txt 文件"
        case .openInTerminal: "以当前位置作为工作目录打开终端"
        }
    }

    var symbolName: String {
        switch self {
        case .copyPath: "point.topleft.down.to.point.bottomright.curvepath"
        case .copyName: "doc.on.doc"
        case .newTextFile: "doc.badge.plus"
        case .openInTerminal: "apple.terminal"
        }
    }
}

struct ApplicationAction: Codable, Identifiable, Equatable {
    let id: String
    let applicationName: String
    let bundleIdentifier: String?
    let applicationPath: String
    var menuTitle: String
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        applicationName: String,
        bundleIdentifier: String?,
        applicationPath: String,
        menuTitle: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.menuTitle = menuTitle ?? "使用 \(applicationName) 打开"
        self.isEnabled = isEnabled
    }

    init(applicationURL: URL) {
        let bundle = Bundle(url: applicationURL)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        self.init(
            applicationName: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            applicationPath: applicationURL.path
        )
    }

    func installedApplicationURL(workspace: NSWorkspace = .shared) -> URL? {
        if let bundleIdentifier,
           let registeredURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return registeredURL
        }
        let savedURL = URL(fileURLWithPath: applicationPath, isDirectory: true)
        return FileManager.default.fileExists(atPath: savedURL.path) ? savedURL : nil
    }
}

enum SharedPreferences {
    static let suiteName = "com.local.RightClickAssistant.shared"
    static let enabledActionIDsKey = "enabledActionIDs"
    static let orderedActionIDsKey = "orderedActionIDs"
    static let applicationActionsKey = "applicationActions"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func orderedActions(defaults: UserDefaults = defaults) -> [QuickAction] {
        let savedIDs = defaults.stringArray(forKey: orderedActionIDsKey) ?? []
        var seen = Set<QuickAction>()
        let saved = savedIDs
            .compactMap(QuickAction.init(rawValue:))
            .filter { seen.insert($0).inserted }
        let missing = QuickAction.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    static func enabledActions(defaults: UserDefaults = defaults) -> [QuickAction] {
        defaults.synchronize()
        guard let savedIDs = defaults.stringArray(forKey: enabledActionIDsKey) else {
            return QuickAction.defaultEnabledActions
        }
        let enabled = Set(savedIDs)
        return orderedActions(defaults: defaults).filter { enabled.contains($0.rawValue) }
    }

    static func applicationActions(defaults: UserDefaults = defaults) -> [ApplicationAction] {
        defaults.synchronize()
        guard let data = defaults.data(forKey: applicationActionsKey),
              let decoded = try? JSONDecoder().decode([ApplicationAction].self, from: data) else {
            return []
        }
        var seen = Set<String>()
        return decoded.filter { seen.insert($0.id).inserted }
    }
}
