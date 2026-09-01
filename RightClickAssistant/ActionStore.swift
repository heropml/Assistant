import AppKit
import Darwin
import Foundation

@MainActor
final class ActionStore: ObservableObject {
    @Published private(set) var configuration: AssistantConfiguration
    @Published private(set) var configurationLoadIssue: ConfigurationLoadIssue?
    @Published private(set) var recoveredConfigurationFromLastKnownGood: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedPreferences.defaults) {
        self.defaults = defaults
        let loadResult = SharedPreferences.loadConfiguration(defaults: defaults)
        configuration = loadResult.configuration
        configurationLoadIssue = loadResult.issue
        recoveredConfigurationFromLastKnownGood = loadResult.recoveredFromLastKnownGood
        if defaults.data(forKey: SharedPreferences.configurationKey) == nil {
            save()
        }
    }

    var actions: [ConfiguredAction] { configuration.actions }
    var groups: [ActionGroup] { configuration.groups }
    var enabledCount: Int { actions.filter(\.isEnabled).count }
    var favoriteCount: Int {
        guard configuration.showsFavoritesAtTopLevel else { return 0 }
        return min(actions.filter { $0.isEnabled && $0.isFavorite }.count, 6)
    }

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

    func moveGroup(_ group: ActionGroup, by offset: Int) {
        guard let source = configuration.groups.firstIndex(where: { $0.id == group.id }) else { return }
        let destination = source + offset
        guard configuration.groups.indices.contains(destination) else { return }
        configuration.groups.swapAt(source, destination)
        save()
    }

    func moveGroup(groupID: String, before targetID: String) {
        guard groupID != targetID,
              let source = configuration.groups.firstIndex(where: { $0.id == groupID }),
              let target = configuration.groups.firstIndex(where: { $0.id == targetID }) else { return }
        let group = configuration.groups.remove(at: source)
        let adjustedTarget = source < target ? target - 1 : target
        configuration.groups.insert(group, at: adjustedTarget)
        save()
    }

    func canMoveGroup(_ group: ActionGroup, by offset: Int) -> Bool {
        guard let index = configuration.groups.firstIndex(where: { $0.id == group.id }) else { return false }
        return configuration.groups.indices.contains(index + offset)
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
        let prepared: (action: ConfiguredAction, urls: [URL])
        do {
            prepared = try HostActionExecutor.prepareExecution(from: url, defaults: defaults)
        } catch let error as HostActionExecutor.ExecutionError {
            if error != .invalidRequest {
                Self.showError("无法执行动作", detail: error.localizedDescription)
            }
            return
        } catch {
            return
        }
        NSApp.hide(nil)
        if prepared.action.kind == .builtIn,
           prepared.action.builtInOperation == .copyPath
                || prepared.action.builtInOperation == .copyName {
            do {
                // NSPasteboard is an AppKit service and must be touched on the
                // main thread. The remaining actions stay off-main because
                // they can perform file I/O or launch external processes.
                try HostActionExecutor.execute(action: prepared.action, urls: prepared.urls)
            } catch {
                Self.showError("动作执行失败", detail: error.localizedDescription)
            }
            return
        }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try HostActionExecutor.execute(action: prepared.action, urls: prepared.urls)
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
        guard SharedPreferences.saveConfiguration(configuration, defaults: defaults) else { return }
        configurationLoadIssue = nil
        recoveredConfigurationFromLastKnownGood = false
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

enum HostActionExecutor {
    private static let scriptOutputLimit = 64 * 1024

    static func prepareExecution(
        from url: URL,
        defaults: UserDefaults
    ) throws -> (action: ConfiguredAction, urls: [URL]) {
        guard let request = SharedPreferences.executionRequest(from: url, defaults: defaults),
              let action = SharedPreferences.configuration(defaults: defaults).actions.first(where: {
                  $0.id == request.actionID
              }) else {
            throw ExecutionError.invalidRequest
        }
        try validateRequest(action: action, urls: request.urls, isContainer: request.isContainer)
        return (action, request.urls)
    }

    static func validateRequest(
        action: ConfiguredAction,
        urls: [URL],
        isContainer: Bool
    ) throws {
        guard action.isEnabled else { throw ExecutionError.actionDisabled }
        guard !urls.isEmpty,
              urls.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") && !$0.path.contains("\0") }) else {
            throw ExecutionError.invalidRequest
        }

        let manager = FileManager.default
        guard urls.allSatisfy({ manager.fileExists(atPath: $0.path) }) else {
            throw ExecutionError.missingTarget
        }
        if isContainer {
            var isDirectory: ObjCBool = false
            guard urls.count == 1,
                  manager.fileExists(atPath: urls[0].path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ExecutionError.invalidRequest
            }
        }

        guard action.conditions.matches(urls: urls, isContainer: isContainer, fileManager: manager) else {
            throw ExecutionError.conditionsNotMet
        }
    }

    static func execute(
        action: ConfiguredAction,
        urls: [URL],
        defaults: UserDefaults = SharedPreferences.defaults,
        revealCreatedFiles: Bool = true,
        scriptTimeout: DispatchTimeInterval = .seconds(30),
        pasteboard: NSPasteboard = .general
    ) throws {
        switch action.kind {
        case .builtIn:
            try executeBuiltIn(action, urls: urls, defaults: defaults, pasteboard: pasteboard)
        case .terminal:
            try openApplication(action, urls: [try workingDirectory(for: urls.first)])
        case .directory:
            guard let targetPath = action.targetPath else { throw ExecutionError.missingTarget }
            let target = try validatedDirectory(URL(fileURLWithPath: targetPath, isDirectory: true))
            guard NSWorkspace.shared.open(target) else { throw ExecutionError.openFailed }
        case .template:
            try createFile(
                from: action,
                in: try workingDirectory(for: urls.first),
                revealInFinder: revealCreatedFiles
            )
        case .shell:
            try runScript(
                action.script,
                executable: "/bin/zsh",
                arguments: shellArguments(action.script, urls: urls),
                urls: urls,
                timeout: scriptTimeout
            )
        case .appleScript:
            try runScript(
                action.script,
                executable: "/usr/bin/osascript",
                arguments: appleScriptArguments(action.script, urls: urls),
                urls: urls,
                timeout: scriptTimeout
            )
        case .application:
            try openApplication(action, urls: urls)
        }
    }

    private static func executeBuiltIn(
        _ action: ConfiguredAction,
        urls: [URL],
        defaults: UserDefaults,
        pasteboard: NSPasteboard
    ) throws {
        switch action.builtInOperation {
        case .copyPath:
            try copy(urls.map(\.path).joined(separator: "\n"), to: pasteboard)
        case .copyName:
            try copy(urls.map(\.lastPathComponent).joined(separator: "\n"), to: pasteboard)
        case .cut:
            guard !urls.isEmpty else { throw ExecutionError.noSelection }
            defaults.set(urls.map(\.path), forKey: SharedPreferences.cutPathsKey)
            defaults.synchronize()
        case .paste:
            guard let firstURL = urls.first else {
                throw ExecutionError.noSelection
            }
            let destination = try workingDirectory(for: firstURL)
            try pasteCutItems(into: destination, defaults: defaults)
        case nil:
            break
        }
    }

    private static func copy(_ value: String, to pasteboard: NSPasteboard) throws {
        guard !value.isEmpty else { throw ExecutionError.noSelection }
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            throw ExecutionError.pasteboardWriteFailed
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
            if source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
                == destination.standardizedFileURL.resolvingSymlinksInPath() {
                continue
            }
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

    private static func createFile(
        from action: ConfiguredAction,
        in directory: URL,
        revealInFinder: Bool
    ) throws {
        let safeDirectory = try validatedDirectory(directory)
        let ext = sanitizedFileComponent(action.normalizedTemplateExtension, fallback: "txt")
        let name = action.title.replacingOccurrences(of: "新建", with: "")
        let baseName = sanitizedFileComponent(name, fallback: "未命名文稿")
        let manager = FileManager.default
        let target = availableURL(for: "\(baseName).\(ext)", in: safeDirectory, manager: manager)
        guard target.deletingLastPathComponent().standardizedFileURL == safeDirectory.standardizedFileURL else {
            throw ExecutionError.invalidFileName
        }
        try Data((action.templateContent ?? "").utf8).write(to: target, options: .atomic)
        if revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
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
        ) { application, error in
            errorBox.set(error ?? (application != nil ? nil : ExecutionError.openFailed))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + .seconds(30)) == .success else {
            throw ExecutionError.openTimedOut
        }
        if let receivedError = errorBox.get() { throw receivedError }
    }

    private static func runScript(
        _ script: String?,
        executable: String,
        arguments: [String],
        urls: [URL],
        timeout: DispatchTimeInterval
    ) throws {
        guard let script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExecutionError.emptyScript
        }
        let workingDirectory = try workingDirectory(for: urls.first)
        var environment = ProcessInfo.processInfo.environment
        environment["RCA_DIRECTORY"] = workingDirectory.path
        environment["RCA_TARGETS"] = urls.map(\.path).joined(separator: "\n")

        let pipe = try makeOutputPipe()
        let collector = BoundedOutputCollector(limit: scriptOutputLimit)
        defer {
            try? pipe.read.close()
            try? pipe.write.close()
        }
        let readFileDescriptor = pipe.read.fileDescriptor
        let writeFileDescriptor = pipe.write.fileDescriptor
        try configurePipeDescriptor(readFileDescriptor, nonBlocking: true)
        try configurePipeDescriptor(writeFileDescriptor, nonBlocking: false)

        let processID = try spawnScriptProcess(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            outputFileDescriptor: writeFileDescriptor
        )
        try? pipe.write.close()

        let deadline = DispatchTime.now() + timeout
        var status: Int32 = 0
        var outputReachedEnd = false
        while true {
            if !outputReachedEnd {
                do {
                    outputReachedEnd = try drainAvailableOutput(
                        from: readFileDescriptor,
                        into: collector
                    )
                } catch {
                    terminateProcessGroup(rootPID: processID)
                    reapProcess(processID)
                    throw error
                }
            }

            let waitResult = waitpid(processID, &status, WNOHANG)
            if waitResult == processID {
                if !outputReachedEnd {
                    _ = try drainAvailableOutput(from: readFileDescriptor, into: collector)
                }
                break
            }
            if waitResult == -1 {
                if errno == EINTR { continue }
                let errorCode = errno
                throw ExecutionError.processWaitFailed(errorCode)
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline.uptimeNanoseconds {
                terminateProcessGroup(rootPID: processID)
                reapProcess(processID)
                if !outputReachedEnd {
                    _ = try? drainAvailableOutput(from: readFileDescriptor, into: collector)
                }
                throw ExecutionError.scriptTimedOut
            }

            let delay = pollingDelayMilliseconds(now: now, deadline: deadline.uptimeNanoseconds)
            if outputReachedEnd {
                Thread.sleep(forTimeInterval: Double(delay) / 1_000)
            } else {
                var descriptor = pollfd(
                    fd: readFileDescriptor,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                )
                let pollResult = Darwin.poll(&descriptor, 1, delay)
                if pollResult == -1, errno != EINTR {
                    let errorCode = errno
                    terminateProcessGroup(rootPID: processID)
                    reapProcess(processID)
                    throw ExecutionError.processIOFailed(errorCode)
                }
            }
        }

        let output = collector.data
        let exitStatus = decodedExitStatus(status)
        guard exitStatus == 0 else {
            var message = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if collector.wasTruncated {
                message = (message ?? "") + "\n（输出已截断）"
            }
            throw ExecutionError.scriptFailed(message?.isEmpty == false ? message! : "退出状态 \(exitStatus)")
        }
    }

    private static func spawnScriptProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        outputFileDescriptor: Int32
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checkPOSIX(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }

        let standardInputResult = "/dev/null".withCString { path in
            posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, path, O_RDONLY, 0)
        }
        try checkPOSIX(standardInputResult)
        try checkPOSIX(posix_spawn_file_actions_adddup2(&fileActions, outputFileDescriptor, STDOUT_FILENO))
        try checkPOSIX(posix_spawn_file_actions_adddup2(&fileActions, outputFileDescriptor, STDERR_FILENO))
        try checkPOSIX(posix_spawn_file_actions_addclose(&fileActions, outputFileDescriptor))
        let changeDirectoryResult = workingDirectory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return EINVAL }
            if #available(macOS 26.0, *) {
                return posix_spawn_file_actions_addchdir(&fileActions, path)
            } else {
                return posix_spawn_file_actions_addchdir_np(&fileActions, path)
            }
        }
        try checkPOSIX(changeDirectoryResult)

        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGPIPE)
        try checkPOSIX(posix_spawnattr_setsigdefault(&attributes, &defaultSignals))
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        try checkPOSIX(posix_spawnattr_setsigmask(&attributes, &signalMask))
        let flags = POSIX_SPAWN_SETSID
            | POSIX_SPAWN_CLOEXEC_DEFAULT
            | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        try checkPOSIX(posix_spawnattr_setflags(&attributes, Int16(flags)))

        let processArguments = [executable] + arguments
        let environmentEntries = environment.map { "\($0.key)=\($0.value)" }
        var processID: pid_t = 0
        let result = try executable.withCString { executablePath in
            try withCStringArray(processArguments) { argumentPointers in
                try withCStringArray(environmentEntries) { environmentPointers in
                    posix_spawn(
                        &processID,
                        executablePath,
                        &fileActions,
                        &attributes,
                        argumentPointers,
                        environmentPointers
                    )
                }
            }
        }
        try checkPOSIX(result)
        return processID
    }

    private static func configurePipeDescriptor(_ descriptor: Int32, nonBlocking: Bool) throws {
        let descriptorFlags = fcntl(descriptor, F_GETFD)
        guard descriptorFlags != -1,
              fcntl(descriptor, F_SETFD, descriptorFlags | FD_CLOEXEC) != -1 else {
            throw ExecutionError.processIOFailed(errno)
        }
        guard nonBlocking else { return }
        let statusFlags = fcntl(descriptor, F_GETFL)
        guard statusFlags != -1,
              fcntl(descriptor, F_SETFL, statusFlags | O_NONBLOCK) != -1 else {
            throw ExecutionError.processIOFailed(errno)
        }
    }

    private static func makeOutputPipe() throws -> (read: FileHandle, write: FileHandle) {
        let pipe = Pipe()
        do {
            let readHandle = try moveAboveStandardDescriptors(pipe.fileHandleForReading)
            let writeHandle = try moveAboveStandardDescriptors(pipe.fileHandleForWriting)
            return (readHandle, writeHandle)
        } catch {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            throw error
        }
    }

    private static func moveAboveStandardDescriptors(_ handle: FileHandle) throws -> FileHandle {
        let descriptor = handle.fileDescriptor
        guard descriptor <= STDERR_FILENO else { return handle }
        let duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
        guard duplicate > STDERR_FILENO else {
            throw ExecutionError.processIOFailed(errno)
        }
        do {
            try handle.close()
        } catch {
            _ = Darwin.close(duplicate)
            throw error
        }
        return FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
    }

    private static func drainAvailableOutput(
        from descriptor: Int32,
        into collector: BoundedOutputCollector
    ) throws -> Bool {
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        for _ in 0..<32 {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead > 0 {
                collector.append(Data(buffer.prefix(bytesRead)))
                continue
            }
            if bytesRead == 0 { return true }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return false }
            throw ExecutionError.processIOFailed(errno)
        }
        return false
    }

    private static func pollingDelayMilliseconds(now: UInt64, deadline: UInt64) -> Int32 {
        let remainingNanoseconds = deadline > now ? deadline - now : 0
        let roundedMilliseconds = remainingNanoseconds / 1_000_000
            + (remainingNanoseconds % 1_000_000 == 0 ? 0 : 1)
        return Int32(max(1, min(50, roundedMilliseconds)))
    }

    private static func reapProcess(_ processID: pid_t) {
        var status: Int32 = 0
        while waitpid(processID, &status, 0) == -1, errno == EINTR {}
    }

    private static func withCStringArray<Result>(
        _ strings: [String],
        operation: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) throws -> Result {
        guard strings.allSatisfy({ !$0.contains("\0") }) else {
            throw ExecutionError.processLaunchFailed(EINVAL)
        }
        var pointers: [UnsafeMutablePointer<CChar>?] = []
        defer { pointers.forEach { free($0) } }
        for string in strings {
            guard let pointer = strdup(string) else {
                throw ExecutionError.processLaunchFailed(ENOMEM)
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try operation(buffer.baseAddress!)
        }
    }

    private static func checkPOSIX(_ result: Int32) throws {
        guard result == 0 else {
            throw ExecutionError.processLaunchFailed(result)
        }
    }

    private static func decodedExitStatus(_ status: Int32) -> Int32 {
        let terminatingSignal = status & 0x7f
        return terminatingSignal == 0 ? (status >> 8) & 0xff : 128 + terminatingSignal
    }

    private static func shellArguments(_ script: String?, urls: [URL]) -> [String] {
        ["-lc", script ?? "", "rightclickassistant"] + urls.map(\.path)
    }

    private static func appleScriptArguments(_ script: String?, urls: [URL]) -> [String] {
        ["-e", script ?? "", "--"] + urls.map(\.path)
    }

    private static func terminateProcessGroup(rootPID: pid_t) {
        guard rootPID > 0 else { return }
        _ = killpg(rootPID, SIGSTOP)
        _ = killpg(rootPID, SIGKILL)
    }

    private static func workingDirectory(for url: URL?) throws -> URL {
        guard let url else { throw ExecutionError.noSelection }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExecutionError.missingTarget
        }
        return try validatedDirectory(isDirectory.boolValue ? url : url.deletingLastPathComponent())
    }

    private static func validatedDirectory(_ url: URL) throws -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ExecutionError.missingTarget
        }
        return resolved
    }

    private static func sanitizedFileComponent(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let parts = value.unicodeScalars.split(whereSeparator: { forbidden.contains($0) })
        let sanitized = parts.map(String.init).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return sanitized.isEmpty || sanitized == "." || sanitized == ".." ? fallback : sanitized
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

    enum ExecutionError: LocalizedError, Equatable {
        case missingTarget
        case noSelection
        case nothingToPaste
        case emptyScript
        case scriptFailed(String)
        case scriptTimedOut
        case invalidRequest
        case actionDisabled
        case conditionsNotMet
        case invalidFileName
        case openFailed
        case openTimedOut
        case processLaunchFailed(Int32)
        case processWaitFailed(Int32)
        case processIOFailed(Int32)
        case pasteboardWriteFailed

        var errorDescription: String? {
            switch self {
            case .missingTarget: "目标应用或目录不存在，请重新编辑此动作。"
            case .noSelection: "没有可处理的文件或目录。"
            case .nothingToPaste: "还没有剪切任何项目。"
            case .emptyScript: "脚本内容为空。"
            case let .scriptFailed(message): "脚本执行失败：\(message)"
            case .scriptTimedOut: "脚本执行超过 30 秒，已停止脚本进程组。"
            case .invalidRequest: "执行请求无效。"
            case .actionDisabled: "该动作已被停用。"
            case .conditionsNotMet: "当前文件或目录不符合动作执行条件。"
            case .invalidFileName: "模板文件名无效。"
            case .openFailed: "系统无法打开目标，请确认目标仍然可用。"
            case .openTimedOut: "系统打开目标超时，请稍后重试。"
            case let .processLaunchFailed(code): "脚本进程启动失败（错误码 \(code)）。"
            case let .processWaitFailed(code): "等待脚本进程失败（错误码 \(code)）。"
            case let .processIOFailed(code): "读取脚本输出失败（错误码 \(code)）。"
            case .pasteboardWriteFailed: "无法写入系统剪贴板。"
            }
        }
    }

    private final class BoundedOutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var buffer = Data()
        private var truncated = false

        init(limit: Int) {
            self.limit = limit
        }

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            let remaining = max(0, limit - buffer.count)
            if remaining > 0 { buffer.append(data.prefix(remaining)) }
            if data.count > remaining { truncated = true }
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }

        var wasTruncated: Bool {
            lock.lock()
            defer { lock.unlock() }
            return truncated
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
