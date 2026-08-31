import AppKit
import Foundation

@MainActor
final class ActionStore: ObservableObject {
    @Published private(set) var configuration: AssistantConfiguration

    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedPreferences.defaults) {
        self.defaults = defaults
        configuration = SharedPreferences.configuration(defaults: defaults)
        if defaults.data(forKey: SharedPreferences.configurationKey) == nil {
            save()
        }
    }

    var actions: [ConfiguredAction] { configuration.actions }
    var groups: [ActionGroup] { configuration.groups }
    var enabledCount: Int { actions.filter(\.isEnabled).count }
    var favoriteCount: Int { actions.filter { $0.isEnabled && $0.isFavorite }.count }

    func upsert(_ action: ConfiguredAction) {
        if let index = configuration.actions.firstIndex(where: { $0.id == action.id }) {
            configuration.actions[index] = action
        } else {
            configuration.actions.append(action)
        }
        save()
    }

    func setEnabled(_ enabled: Bool, for action: ConfiguredAction) {
        update(action.id) { $0.isEnabled = enabled }
    }

    func setFavorite(_ favorite: Bool, for action: ConfiguredAction) {
        update(action.id) { $0.isFavorite = favorite }
    }

    func remove(_ action: ConfiguredAction) {
        configuration.actions.removeAll { $0.id == action.id }
        save()
    }

    func move(_ action: ConfiguredAction, by offset: Int) {
        guard let source = configuration.actions.firstIndex(where: { $0.id == action.id }) else { return }
        let destination = source + offset
        guard configuration.actions.indices.contains(destination) else { return }
        configuration.actions.swapAt(source, destination)
        save()
    }

    func move(actionID: String, before targetID: String) {
        guard actionID != targetID,
              let source = configuration.actions.firstIndex(where: { $0.id == actionID }),
              let target = configuration.actions.firstIndex(where: { $0.id == targetID }) else { return }
        let action = configuration.actions.remove(at: source)
        let adjustedTarget = source < target ? target - 1 : target
        configuration.actions.insert(action, at: adjustedTarget)
        save()
    }

    func canMove(_ action: ConfiguredAction, by offset: Int) -> Bool {
        guard let index = configuration.actions.firstIndex(where: { $0.id == action.id }) else { return false }
        return configuration.actions.indices.contains(index + offset)
    }

    func addGroup(title: String, symbolName: String = "folder") {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configuration.groups.append(ActionGroup(title: trimmed, symbolName: symbolName))
        save()
    }

    func updateGroup(_ group: ActionGroup) {
        guard let index = configuration.groups.firstIndex(where: { $0.id == group.id }) else { return }
        configuration.groups[index] = group
        save()
    }

    func removeGroup(_ group: ActionGroup) {
        configuration.groups.removeAll { $0.id == group.id }
        for index in configuration.actions.indices where configuration.actions[index].groupID == group.id {
            configuration.actions[index].groupID = nil
        }
        save()
    }

    func setShowsFavoritesAtTopLevel(_ enabled: Bool) {
        configuration.showsFavoritesAtTopLevel = enabled
        save()
    }

    func draft(for kind: ActionKind) -> ConfiguredAction {
        switch kind {
        case .builtIn:
            ConfiguredAction(kind: .builtIn, title: "新动作", builtInOperation: .copyPath)
        case .application:
            ConfiguredAction(kind: .application, title: "使用应用打开")
        case .terminal:
            ConfiguredAction(kind: .terminal, title: "在终端打开", symbolName: "apple.terminal")
        case .directory:
            ConfiguredAction(kind: .directory, title: "打开常用目录", symbolName: "folder")
        case .template:
            ConfiguredAction(
                kind: .template,
                title: "新建文件",
                symbolName: "doc.badge.plus",
                conditions: ActionConditions(allowsFiles: false, allowsFolders: true, allowsContainer: true),
                templateExtension: "txt",
                templateContent: ""
            )
        case .shell:
            ConfiguredAction(kind: .shell, title: "运行 Shell 脚本", script: "")
        case .appleScript:
            ConfiguredAction(kind: .appleScript, title: "运行 AppleScript", script: "")
        }
    }

    func action(fromApplicationURL url: URL, kind: ActionKind) -> ConfiguredAction {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ConfiguredAction(
            kind: kind,
            title: kind == .terminal ? "在 \(name) 打开" : "使用 \(name) 打开",
            symbolName: kind.symbolName,
            targetPath: url.path,
            bundleIdentifier: bundle?.bundleIdentifier
        )
    }

    func action(fromDirectoryURL url: URL) -> ConfiguredAction {
        ConfiguredAction(
            kind: .directory,
            title: "打开 \(url.lastPathComponent)",
            symbolName: "folder",
            targetPath: url.path
        )
    }

    func handleExecutionURL(_ url: URL) {
        guard let request = SharedPreferences.executionRequest(from: url),
              let action = SharedPreferences.configuration(defaults: defaults).actions.first(where: { $0.id == request.actionID }) else {
            return
        }
        NSApp.hide(nil)
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try HostActionExecutor.execute(action: action, urls: request.urls)
                }.value
            } catch {
                Self.showError("动作执行失败", detail: error.localizedDescription)
            }
        }
    }

    private func update(_ id: String, change: (inout ConfiguredAction) -> Void) {
        guard let index = configuration.actions.firstIndex(where: { $0.id == id }) else { return }
        change(&configuration.actions[index])
        save()
    }

    private func save() {
        configuration = configuration.normalized()
        guard let data = SharedPreferences.encoded(configuration) else { return }
        defaults.set(data, forKey: SharedPreferences.configurationKey)
        defaults.synchronize()
    }

    private static func showError(_ message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private enum HostActionExecutor {
    static func execute(action: ConfiguredAction, urls: [URL]) throws {
        let defaults = SharedPreferences.defaults
        switch action.kind {
        case .builtIn:
            try executeBuiltIn(action, urls: urls, defaults: defaults)
        case .terminal:
            try openApplication(action, urls: [workingDirectory(for: urls.first)])
        case .directory:
            guard let targetPath = action.targetPath else { throw ExecutionError.missingTarget }
            NSWorkspace.shared.open(URL(fileURLWithPath: targetPath, isDirectory: true))
        case .template:
            try createFile(from: action, in: workingDirectory(for: urls.first))
        case .shell:
            try runScript(action.script, executable: "/bin/zsh", arguments: shellArguments(action.script, urls: urls), urls: urls)
        case .appleScript:
            try runScript(action.script, executable: "/usr/bin/osascript", arguments: appleScriptArguments(action.script, urls: urls), urls: urls)
        case .application:
            try openApplication(action, urls: urls)
        }
    }

    private static func executeBuiltIn(_ action: ConfiguredAction, urls: [URL], defaults: UserDefaults) throws {
        switch action.builtInOperation {
        case .cut:
            guard !urls.isEmpty else { throw ExecutionError.noSelection }
            defaults.set(urls.map(\.path), forKey: SharedPreferences.cutPathsKey)
            defaults.synchronize()
        case .paste:
            guard let destination = urls.first.map({ workingDirectory(for: $0) }) else {
                throw ExecutionError.noSelection
            }
            try pasteCutItems(into: destination, defaults: defaults)
        case .copyPath, .copyName, nil:
            break
        }
    }

    private static func pasteCutItems(into destination: URL, defaults: UserDefaults) throws {
        let paths = defaults.stringArray(forKey: SharedPreferences.cutPathsKey) ?? []
        guard !paths.isEmpty else { throw ExecutionError.nothingToPaste }
        let manager = FileManager.default
        var remaining: [String] = []
        var firstError: Error?

        for path in paths {
            let source = URL(fileURLWithPath: path)
            guard manager.fileExists(atPath: source.path) else { continue }
            let target = availableURL(for: source.lastPathComponent, in: destination, manager: manager)
            do {
                try manager.moveItem(at: source, to: target)
            } catch {
                remaining.append(path)
                if firstError == nil { firstError = error }
            }
        }

        defaults.set(remaining, forKey: SharedPreferences.cutPathsKey)
        defaults.synchronize()
        if let firstError { throw firstError }
    }

    private static func createFile(from action: ConfiguredAction, in directory: URL) throws {
        let ext = action.normalizedTemplateExtension.isEmpty ? "txt" : action.normalizedTemplateExtension
        let name = action.title.replacingOccurrences(of: "新建", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = name.isEmpty ? "未命名文稿" : name
        let manager = FileManager.default
        let target = availableURL(for: "\(baseName).\(ext)", in: directory, manager: manager)
        try Data((action.templateContent ?? "").utf8).write(to: target, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private static func openApplication(_ action: ConfiguredAction, urls: [URL]) throws {
        guard !urls.isEmpty else { throw ExecutionError.noSelection }
        guard let applicationURL = action.installedApplicationURL() else { throw ExecutionError.missingTarget }
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            errorBox.set(error)
            semaphore.signal()
        }
        semaphore.wait()
        if let receivedError = errorBox.get() { throw receivedError }
    }

    private static func runScript(
        _ script: String?,
        executable: String,
        arguments: [String],
        urls: [URL]
    ) throws {
        guard let script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExecutionError.emptyScript
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory(for: urls.first)
        var environment = ProcessInfo.processInfo.environment
        environment["RCA_DIRECTORY"] = process.currentDirectoryURL?.path
        environment["RCA_TARGETS"] = urls.map(\.path).joined(separator: "\n")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ExecutionError.scriptFailed(message?.isEmpty == false ? message! : "退出状态 \(process.terminationStatus)")
        }
    }

    private static func shellArguments(_ script: String?, urls: [URL]) -> [String] {
        ["-lc", script ?? "", "rightclickassistant"] + urls.map(\.path)
    }

    private static func appleScriptArguments(_ script: String?, urls: [URL]) -> [String] {
        ["-e", script ?? "", "--"] + urls.map(\.path)
    }

    private static func workingDirectory(for url: URL?) -> URL {
        guard let url else { return FileManager.default.homeDirectoryForCurrentUser }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private static func availableURL(for fileName: String, in directory: URL, manager: FileManager) -> URL {
        let original = directory.appendingPathComponent(fileName)
        guard manager.fileExists(atPath: original.path) else { return original }
        let source = URL(fileURLWithPath: fileName)
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private enum ExecutionError: LocalizedError {
        case missingTarget
        case noSelection
        case nothingToPaste
        case emptyScript
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingTarget: "目标应用或目录不存在，请重新编辑此动作。"
            case .noSelection: "没有可处理的文件或目录。"
            case .nothingToPaste: "还没有剪切任何项目。"
            case .emptyScript: "脚本内容为空。"
            case let .scriptFailed(message): "脚本执行失败：\(message)"
            }
        }
    }

    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Error?

        func set(_ error: Error?) {
            lock.lock()
            value = error
            lock.unlock()
        }

        func get() -> Error? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
