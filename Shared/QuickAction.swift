import AppKit
import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case builtIn
    case application
    case terminal
    case directory
    case template
    case shell
    case appleScript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: "基础动作"
        case .application: "应用"
        case .terminal: "终端"
        case .directory: "常用目录"
        case .template: "文件模板"
        case .shell: "Shell"
        case .appleScript: "AppleScript"
        }
    }

    var symbolName: String {
        switch self {
        case .builtIn: "cursorarrow.click.2"
        case .application: "app"
        case .terminal: "apple.terminal"
        case .directory: "folder"
        case .template: "doc.badge.plus"
        case .shell: "chevron.left.forwardslash.chevron.right"
        case .appleScript: "applescript"
        }
    }
}

enum BuiltInOperation: String, Codable, Sendable {
    case copyPath
    case copyName
    case cut
    case paste
}

struct ActionConditions: Codable, Equatable, Sendable {
    var allowsFiles: Bool
    var allowsFolders: Bool
    var allowsContainer: Bool
    var fileExtensions: [String]
    var minimumSelectionCount: Int
    var maximumSelectionCount: Int?
    var pathPrefixes: [String]

    init(
        allowsFiles: Bool = true,
        allowsFolders: Bool = true,
        allowsContainer: Bool = true,
        fileExtensions: [String] = [],
        minimumSelectionCount: Int = 1,
        maximumSelectionCount: Int? = nil,
        pathPrefixes: [String] = []
    ) {
        self.allowsFiles = allowsFiles
        self.allowsFolders = allowsFolders
        self.allowsContainer = allowsContainer
        self.fileExtensions = Self.normalizeExtensions(fileExtensions)
        self.minimumSelectionCount = max(1, minimumSelectionCount)
        self.maximumSelectionCount = maximumSelectionCount
        self.pathPrefixes = pathPrefixes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowsFiles = try container.decodeIfPresent(Bool.self, forKey: .allowsFiles) ?? true
        allowsFolders = try container.decodeIfPresent(Bool.self, forKey: .allowsFolders) ?? true
        allowsContainer = try container.decodeIfPresent(Bool.self, forKey: .allowsContainer) ?? true
        fileExtensions = Self.normalizeExtensions(
            try container.decodeIfPresent([String].self, forKey: .fileExtensions) ?? []
        )
        minimumSelectionCount = max(1, try container.decodeIfPresent(Int.self, forKey: .minimumSelectionCount) ?? 1)
        maximumSelectionCount = try container.decodeIfPresent(Int.self, forKey: .maximumSelectionCount)
        pathPrefixes = try container.decodeIfPresent([String].self, forKey: .pathPrefixes) ?? []
    }

    func matches(urls: [URL], isContainer: Bool, fileManager: FileManager = .default) -> Bool {
        guard !urls.isEmpty else { return false }
        if isContainer {
            return allowsContainer && matchesPaths(urls)
        }

        guard urls.count >= minimumSelectionCount else { return false }
        if let maximumSelectionCount, urls.count > maximumSelectionCount { return false }

        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists && isDirectory.boolValue {
                guard allowsFolders else { return false }
            } else {
                guard allowsFiles else { return false }
                if !fileExtensions.isEmpty {
                    let ext = url.pathExtension.lowercased()
                    guard fileExtensions.contains(ext) else { return false }
                }
            }
        }
        return matchesPaths(urls)
    }

    static func normalizeExtensions(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func matchesPaths(_ urls: [URL]) -> Bool {
        guard !pathPrefixes.isEmpty else { return true }
        return urls.allSatisfy { url in
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            return pathPrefixes.contains { rawPrefix in
                let prefix = URL(fileURLWithPath: rawPrefix, isDirectory: true)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .path
                if prefix == "/" {
                    return path.hasPrefix("/")
                }
                return path == prefix || path.hasPrefix(prefix + "/")
            }
        }
    }
}

struct ConfiguredAction: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: ActionKind
    var title: String
    var symbolName: String
    var isEnabled: Bool
    var isFavorite: Bool
    var groupID: String?
    var conditions: ActionConditions

    var builtInOperation: BuiltInOperation?
    var targetPath: String?
    var bundleIdentifier: String?
    var templateExtension: String?
    var templateContent: String?
    var script: String?

    init(
        id: String = UUID().uuidString,
        kind: ActionKind,
        title: String,
        symbolName: String? = nil,
        isEnabled: Bool = true,
        isFavorite: Bool = false,
        groupID: String? = nil,
        conditions: ActionConditions = ActionConditions(),
        builtInOperation: BuiltInOperation? = nil,
        targetPath: String? = nil,
        bundleIdentifier: String? = nil,
        templateExtension: String? = nil,
        templateContent: String? = nil,
        script: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.symbolName = symbolName ?? kind.symbolName
        self.isEnabled = isEnabled
        self.isFavorite = isFavorite
        self.groupID = groupID
        self.conditions = conditions
        self.builtInOperation = builtInOperation
        self.targetPath = targetPath
        self.bundleIdentifier = bundleIdentifier
        self.templateExtension = templateExtension
        self.templateContent = templateContent
        self.script = script
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decode(ActionKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? kind.symbolName
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        conditions = try container.decodeIfPresent(ActionConditions.self, forKey: .conditions) ?? ActionConditions()
        builtInOperation = try container.decodeIfPresent(BuiltInOperation.self, forKey: .builtInOperation)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        templateExtension = try container.decodeIfPresent(String.self, forKey: .templateExtension)
        templateContent = try container.decodeIfPresent(String.self, forKey: .templateContent)
        script = try container.decodeIfPresent(String.self, forKey: .script)
    }

    var detail: String {
        switch kind {
        case .builtIn:
            switch builtInOperation {
            case .copyPath: "复制所选项目的完整路径"
            case .copyName: "复制所选项目的名称"
            case .cut: "记录所选项目，稍后移动到目标文件夹"
            case .paste: "把已剪切项目移动到当前文件夹"
            case nil: "基础 Finder 动作"
            }
        case .application: targetPath ?? "选择一个应用"
        case .terminal: targetPath ?? "选择一个终端应用"
        case .directory: targetPath ?? "选择一个常用目录"
        case .template: "新建 .\(normalizedTemplateExtension) 文件"
        case .shell: "通过 zsh 执行；所选路径作为位置参数传入"
        case .appleScript: "通过 osascript 执行；所选路径作为参数传入"
        }
    }

    var normalizedTemplateExtension: String {
        let value = (templateExtension ?? "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix(".") ? String(value.dropFirst()) : value
    }

    func installedApplicationURL(workspace: NSWorkspace = .shared) -> URL? {
        if let bundleIdentifier,
           let registeredURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return registeredURL
        }
        guard let targetPath else { return nil }
        return FileManager.default.fileExists(atPath: targetPath)
            ? URL(fileURLWithPath: targetPath, isDirectory: true)
            : nil
    }

    func matches(urls: [URL], isContainer: Bool) -> Bool {
        isEnabled && conditions.matches(urls: urls, isContainer: isContainer)
    }
}

struct ActionGroup: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var symbolName: String

    init(id: String = UUID().uuidString, title: String, symbolName: String = "folder") {
        self.id = id
        self.title = title
        self.symbolName = symbolName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "folder"
    }
}

struct AssistantConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var version: Int
    var actions: [ConfiguredAction]
    var groups: [ActionGroup]
    var showsFavoritesAtTopLevel: Bool

    init(
        version: Int = currentVersion,
        actions: [ConfiguredAction],
        groups: [ActionGroup],
        showsFavoritesAtTopLevel: Bool = true
    ) {
        self.version = version
        self.actions = actions
        self.groups = groups
        self.showsFavoritesAtTopLevel = showsFavoritesAtTopLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        actions = try container.decodeIfPresent([ConfiguredAction].self, forKey: .actions) ?? []
        groups = try container.decodeIfPresent([ActionGroup].self, forKey: .groups) ?? []
        showsFavoritesAtTopLevel = try container.decodeIfPresent(Bool.self, forKey: .showsFavoritesAtTopLevel) ?? true
    }

    static var defaultValue: AssistantConfiguration {
        let files = ActionGroup(id: "files", title: "文件", symbolName: "folder.fill")
        let open = ActionGroup(id: "open", title: "打开方式", symbolName: "arrow.up.forward.app")
        return AssistantConfiguration(
            actions: [
                ConfiguredAction(
                    id: "builtin.copyPath",
                    kind: .builtIn,
                    title: "复制路径",
                    symbolName: "point.topleft.down.to.point.bottomright.curvepath",
                    isFavorite: true,
                    groupID: files.id,
                    builtInOperation: .copyPath
                ),
                ConfiguredAction(
                    id: "builtin.copyName",
                    kind: .builtIn,
                    title: "复制文件名",
                    symbolName: "doc.on.doc",
                    groupID: files.id,
                    builtInOperation: .copyName
                ),
                ConfiguredAction(
                    id: "builtin.cut",
                    kind: .builtIn,
                    title: "剪切",
                    symbolName: "scissors",
                    groupID: files.id,
                    conditions: ActionConditions(allowsContainer: false),
                    builtInOperation: .cut
                ),
                ConfiguredAction(
                    id: "builtin.paste",
                    kind: .builtIn,
                    title: "粘贴已剪切项目",
                    symbolName: "doc.on.clipboard",
                    groupID: files.id,
                    conditions: ActionConditions(allowsFiles: false, allowsFolders: true, allowsContainer: true),
                    builtInOperation: .paste
                ),
                ConfiguredAction(
                    id: "template.text",
                    kind: .template,
                    title: "新建文本文件",
                    symbolName: "doc.badge.plus",
                    isFavorite: true,
                    groupID: files.id,
                    conditions: ActionConditions(allowsFiles: false, allowsFolders: true, allowsContainer: true),
                    templateExtension: "txt",
                    templateContent: ""
                ),
                ConfiguredAction(
                    id: "terminal.system",
                    kind: .terminal,
                    title: "在终端打开",
                    symbolName: "apple.terminal",
                    isFavorite: true,
                    groupID: open.id,
                    targetPath: "/System/Applications/Utilities/Terminal.app",
                    bundleIdentifier: "com.apple.Terminal"
                )
            ],
            groups: [files, open]
        )
    }

    func normalized() -> AssistantConfiguration {
        var copy = self
        var seenActions = Set<String>()
        copy.actions = actions.filter { seenActions.insert($0.id).inserted }
        var seenGroups = Set<String>()
        copy.groups = groups.filter { seenGroups.insert($0.id).inserted }
        if version < 3,
           let filesGroupIndex = copy.groups.firstIndex(where: {
               $0.id == "files" && $0.symbolName == "doc.on.doc"
           }) {
            copy.groups[filesGroupIndex].symbolName = "folder.fill"
        }
        let validGroups = Set(copy.groups.map(\.id))
        for index in copy.actions.indices where copy.actions[index].groupID.map({ !validGroups.contains($0) }) == true {
            copy.actions[index].groupID = nil
        }
        copy.version = Self.currentVersion
        return copy
    }
}

enum ConfigurationLoadIssue: Equatable, Sendable {
    case corruptedData
    case unsupportedVersion(Int)

    fileprivate var persistedValue: String {
        switch self {
        case .corruptedData:
            return "corruptedData"
        case let .unsupportedVersion(version):
            return "unsupportedVersion:\(version)"
        }
    }
}

struct ConfigurationLoadResult: Equatable, Sendable {
    var configuration: AssistantConfiguration
    var issue: ConfigurationLoadIssue?
    var recoveredFromLastKnownGood: Bool
}

struct ExecutionRequest: Codable, Equatable, Sendable {
    let id: String
    let actionID: String
    let paths: [String]
    let isContainer: Bool
    let createdAt: Date

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
}

enum SharedPreferences {
    static let suiteName = "com.local.RightClickAssistant.shared"
    static let configurationKey = "configurationV2"
    static let cutPathsKey = "cutPathsV2"
    static let lastKnownGoodConfigurationKey = "configurationV2.lastKnownGood"
    static let configurationRecoveryDataKey = "configurationV2.recoveryData"
    static let previousConfigurationRecoveryDataKey = "configurationV2.previousRecoveryData"
    static let configurationLoadIssueKey = "configurationV2.loadIssue"

    private static let executionRequestKeyPrefix = "executionRequestV1."
    private static let executionRequestLifetime: TimeInterval = 30
    private static let maximumExecutionTargets = 4_096

    private static let legacyEnabledActionIDsKey = "enabledActionIDs"
    private static let legacyOrderedActionIDsKey = "orderedActionIDs"
    private static let legacyApplicationActionsKey = "applicationActions"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func configuration(defaults: UserDefaults = defaults) -> AssistantConfiguration {
        loadConfiguration(defaults: defaults).configuration
    }

    static func loadConfiguration(defaults: UserDefaults = defaults) -> ConfigurationLoadResult {
        defaults.synchronize()
        guard let data = defaults.data(forKey: configurationKey) else {
            if let lastKnownGoodData = defaults.data(forKey: lastKnownGoodConfigurationKey),
               let lastKnownGood = try? JSONDecoder().decode(
                   AssistantConfiguration.self,
                   from: lastKnownGoodData
               ),
               lastKnownGood.version <= AssistantConfiguration.currentVersion {
                let restored = lastKnownGood.normalized()
                if canPersistRecoveryState, let restoredData = encoded(restored) {
                    defaults.set(restoredData, forKey: configurationKey)
                    defaults.removeObject(forKey: configurationLoadIssueKey)
                    defaults.synchronize()
                }
                return ConfigurationLoadResult(
                    configuration: restored,
                    issue: nil,
                    recoveredFromLastKnownGood: true
                )
            }
            let migrated = migrateLegacy(defaults: defaults)
            rememberLastKnownGood(migrated, defaults: defaults)
            return ConfigurationLoadResult(
                configuration: migrated,
                issue: nil,
                recoveredFromLastKnownGood: false
            )
        }

        do {
            if let version = try? JSONDecoder().decode(ConfigurationVersionEnvelope.self, from: data).version,
               version > AssistantConfiguration.currentVersion {
                return recover(
                    from: data,
                    issue: .unsupportedVersion(version),
                    defaults: defaults
                )
            }
            let decoded = try JSONDecoder().decode(AssistantConfiguration.self, from: data)
            let normalized = decoded.normalized()
            if canPersistRecoveryState,
               normalized != decoded,
               let normalizedData = encoded(normalized) {
                defaults.set(normalizedData, forKey: configurationKey)
                defaults.synchronize()
            }
            rememberLastKnownGood(normalized, defaults: defaults)
            if canPersistRecoveryState {
                defaults.removeObject(forKey: configurationLoadIssueKey)
            }
            return ConfigurationLoadResult(
                configuration: normalized,
                issue: nil,
                recoveredFromLastKnownGood: false
            )
        } catch {
            return recover(from: data, issue: .corruptedData, defaults: defaults)
        }
    }

    static func encoded(_ configuration: AssistantConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration.normalized())
    }

    @discardableResult
    static func saveConfiguration(
        _ configuration: AssistantConfiguration,
        defaults: UserDefaults = defaults
    ) -> Bool {
        guard let data = encoded(configuration) else { return false }
        defaults.set(data, forKey: configurationKey)
        defaults.set(data, forKey: lastKnownGoodConfigurationKey)
        defaults.removeObject(forKey: configurationLoadIssueKey)
        defaults.synchronize()
        return true
    }

    static func executionURL(
        actionID: String,
        urls: [URL],
        isContainer: Bool,
        defaults: UserDefaults = defaults,
        createdAt: Date = Date()
    ) -> URL? {
        let paths = urls.map { $0.standardizedFileURL.path }
        guard !actionID.isEmpty,
              !paths.isEmpty,
              paths.count <= maximumExecutionTargets,
              zip(urls, paths).allSatisfy({ url, path in
                  url.isFileURL && path.hasPrefix("/") && !path.contains("\0")
              }) else {
            return nil
        }

        let requestID = UUID().uuidString
        let request = ExecutionRequest(
            id: requestID,
            actionID: actionID,
            paths: paths,
            isContainer: isContainer,
            createdAt: createdAt
        )
        guard let data = try? JSONEncoder().encode(request) else { return nil }
        purgeExpiredExecutionRequests(defaults: defaults, now: createdAt)
        defaults.set(data, forKey: executionRequestKeyPrefix + requestID)
        defaults.synchronize()

        var components = URLComponents()
        components.scheme = "rightclickassistant"
        components.host = "execute"
        components.queryItems = [URLQueryItem(name: "request", value: requestID)]
        return components.url
    }

    static func executionRequest(
        from url: URL,
        defaults: UserDefaults = defaults,
        now: Date = Date()
    ) -> ExecutionRequest? {
        defaults.synchronize()
        guard url.scheme == "rightclickassistant", url.host == "execute",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "request",
              let requestID = queryItems[0].value,
              UUID(uuidString: requestID) != nil else {
            return nil
        }

        let key = executionRequestKeyPrefix + requestID
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        defaults.synchronize()

        guard let request = try? JSONDecoder().decode(ExecutionRequest.self, from: data),
              request.id == requestID,
              !request.actionID.isEmpty,
              !request.paths.isEmpty,
              request.paths.count <= maximumExecutionTargets,
              request.paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }),
              now.timeIntervalSince(request.createdAt) >= -5,
              now.timeIntervalSince(request.createdAt) <= executionRequestLifetime else {
            return nil
        }
        return request
    }

    static func discardExecutionRequest(
        from url: URL,
        defaults: UserDefaults = defaults
    ) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestID = components.queryItems?.first(where: { $0.name == "request" })?.value,
              UUID(uuidString: requestID) != nil else { return }
        defaults.removeObject(forKey: executionRequestKeyPrefix + requestID)
        defaults.synchronize()
    }

    private static func purgeExpiredExecutionRequests(defaults: UserDefaults, now: Date) {
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(executionRequestKeyPrefix) {
            guard let data = value as? Data,
                  let request = try? JSONDecoder().decode(ExecutionRequest.self, from: data),
                  now.timeIntervalSince(request.createdAt) >= -5,
                  now.timeIntervalSince(request.createdAt) <= executionRequestLifetime else {
                defaults.removeObject(forKey: key)
                continue
            }
        }
    }

    private static func migrateLegacy(defaults: UserDefaults) -> AssistantConfiguration {
        var configuration = AssistantConfiguration.defaultValue
        let mapping = [
            "copyPath": "builtin.copyPath",
            "copyName": "builtin.copyName",
            "newTextFile": "template.text",
            "openInTerminal": "terminal.system"
        ]

        if let legacyOrder = defaults.stringArray(forKey: legacyOrderedActionIDsKey) {
            let orderedIDs = legacyOrder.compactMap { mapping[$0] }
            configuration.actions.sort { lhs, rhs in
                (orderedIDs.firstIndex(of: lhs.id) ?? Int.max) < (orderedIDs.firstIndex(of: rhs.id) ?? Int.max)
            }
        }

        if defaults.object(forKey: legacyEnabledActionIDsKey) != nil {
            let enabled = Set(defaults.stringArray(forKey: legacyEnabledActionIDsKey) ?? [])
            for index in configuration.actions.indices {
                let legacyID = mapping.first(where: { $0.value == configuration.actions[index].id })?.key
                configuration.actions[index].isEnabled = legacyID.map(enabled.contains) ?? false
            }
        }

        if let data = defaults.data(forKey: legacyApplicationActionsKey),
           let applications = try? JSONDecoder().decode([LegacyApplicationAction].self, from: data) {
            let openGroup = configuration.groups.first(where: { $0.id == "open" })?.id
            configuration.actions.append(contentsOf: applications.map {
                ConfiguredAction(
                    id: $0.id,
                    kind: .application,
                    title: $0.menuTitle,
                    symbolName: "app",
                    isEnabled: $0.isEnabled,
                    groupID: openGroup,
                    targetPath: $0.applicationPath,
                    bundleIdentifier: $0.bundleIdentifier
                )
            })
        }
        return configuration.normalized()
    }

    private static var canPersistRecoveryState: Bool {
        Bundle.main.bundleIdentifier != "com.local.RightClickAssistant.FinderExtension"
    }

    private static func rememberLastKnownGood(
        _ configuration: AssistantConfiguration,
        defaults: UserDefaults
    ) {
        guard canPersistRecoveryState, let data = encoded(configuration) else { return }
        defaults.set(data, forKey: lastKnownGoodConfigurationKey)
        defaults.synchronize()
    }

    private static func recover(
        from failedData: Data,
        issue: ConfigurationLoadIssue,
        defaults: UserDefaults
    ) -> ConfigurationLoadResult {
        if canPersistRecoveryState {
            if let currentRecovery = defaults.data(forKey: configurationRecoveryDataKey),
               currentRecovery != failedData {
                defaults.set(currentRecovery, forKey: previousConfigurationRecoveryDataKey)
            }
            defaults.set(failedData, forKey: configurationRecoveryDataKey)
            defaults.set(issue.persistedValue, forKey: configurationLoadIssueKey)
            defaults.synchronize()
        }

        if let lastKnownGoodData = defaults.data(forKey: lastKnownGoodConfigurationKey),
           let lastKnownGood = try? JSONDecoder().decode(AssistantConfiguration.self, from: lastKnownGoodData),
           lastKnownGood.version <= AssistantConfiguration.currentVersion {
            return ConfigurationLoadResult(
                configuration: lastKnownGood.normalized(),
                issue: issue,
                recoveredFromLastKnownGood: true
            )
        }

        return ConfigurationLoadResult(
            configuration: AssistantConfiguration(
                actions: [],
                groups: [],
                showsFavoritesAtTopLevel: false
            ),
            issue: issue,
            recoveredFromLastKnownGood: false
        )
    }
}

private struct ConfigurationVersionEnvelope: Decodable {
    let version: Int
}

private struct LegacyApplicationAction: Codable {
    let id: String
    let bundleIdentifier: String?
    let applicationPath: String
    let menuTitle: String
    let isEnabled: Bool
}
