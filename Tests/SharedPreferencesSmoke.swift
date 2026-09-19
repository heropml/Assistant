import Foundation

private final class CountingFileManager: FileManager, @unchecked Sendable {
    private(set) var queryCount = 0

    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        queryCount += 1
        return super.fileExists(atPath: path, isDirectory: isDirectory)
    }
}

@main
struct SharedPreferencesSmoke {
    static func main() throws {
        let suiteName = "com.local.RightClickAssistant.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("无法创建测试偏好域")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        testDefaults(defaults)
        try testLegacyMigration(defaults)
        try testLegacyMigrationEdgeCases(defaults)
        testConditions()
        testConfigurationRoundTrip(defaults)
        try testV2GroupIconMigration(defaults)
        try testConfigurationRecovery(defaults)
        try testForwardCompatibleDecode()
        testExecutionURL(defaults)
        try testConfigurationTransfer()
        try testConfigurationCache(defaults)
        try testSharedMatchContext()

        print("V3 共享配置测试通过")
    }

    private static func testConfigurationTransfer() throws {
        let original = AssistantConfiguration.defaultValue
        let restored = try ConfigurationTransfer.decode(ConfigurationTransfer.encode(original))
        precondition(restored == original.normalized())
        let empty = AssistantConfiguration(actions: [], groups: [])
        let emptyRestored = try ConfigurationTransfer.decode(ConfigurationTransfer.encode(empty))
        precondition(emptyRestored == empty)

        var future = original
        future.version = AssistantConfiguration.currentVersion + 1
        var duplicate = original
        duplicate.actions.append(duplicate.actions[0])
        var orphan = original
        orphan.actions[0].groupID = "missing-group"
        var blank = original
        blank.actions[0].title = "  "
        var malformedBuiltIn = original
        malformedBuiltIn.actions[0].builtInOperation = nil
        let invalidData = try [future, duplicate, orphan, blank, malformedBuiltIn].map { try JSONEncoder().encode($0) }
            + [Data("{}".utf8), Data("not-json".utf8)]
        for data in invalidData {
            do {
                _ = try ConfigurationTransfer.decode(data)
                preconditionFailure("无效导入必须被拒绝")
            } catch {}
        }
        var older = original
        older.version = 2
        let upgraded = try ConfigurationTransfer.decode(JSONEncoder().encode(older))
        precondition(upgraded == older.normalized())
    }

    private static func testConfigurationCache(_ defaults: UserDefaults) throws {
        let cache = SharedConfigurationCache(defaults: defaults)
        var configuration = AssistantConfiguration.defaultValue
        precondition(SharedPreferences.saveConfiguration(configuration, defaults: defaults))
        precondition(cache.configuration() == configuration)
        precondition(cache.configuration() == configuration)
        configuration.actions[0].isEnabled.toggle()
        precondition(SharedPreferences.saveConfiguration(configuration, defaults: defaults))
        precondition(cache.configuration() == configuration, "缓存必须读取配置变更")
        defaults.set(Data("corrupt".utf8), forKey: SharedPreferences.configurationKey)
        precondition(cache.configuration() == configuration, "损坏配置仍应恢复备份")
        defaults.removeObject(forKey: SharedPreferences.configurationKey)
        precondition(cache.configuration() == configuration)
        let empty = AssistantConfiguration(actions: [], groups: [])
        precondition(SharedPreferences.saveConfiguration(empty, defaults: defaults))
        precondition(cache.configuration() == empty, "导入空配置后不能显示旧动作")
    }

    private static func testSharedMatchContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("readme.MD")
        try Data().write(to: file)
        let manager = CountingFileManager()
        let context = ActionMatchContext(urls: [file, directory], isContainer: false, fileManager: manager)
        let unrestricted = ActionConditions()
        let scoped = ActionConditions(fileExtensions: ["md"], pathPrefixes: [directory.path])
        for _ in 0..<100 {
            precondition(unrestricted.matches(context: context))
            precondition(scoped.matches(context: context))
        }
        precondition(manager.queryCount == 2, "各动作应复用文件元数据")
        precondition(!ActionConditions(allowsFolders: false).matches(context: context))
        precondition(!ActionConditions(maximumSelectionCount: 1).matches(context: context))

        let container = ActionMatchContext(urls: [directory], isContainer: true, fileManager: manager)
        precondition(scoped.matches(context: container))
        precondition(manager.queryCount == 2, "空白处条件无需查询文件类型")
        precondition(!ActionConditions(allowsContainer: false).matches(context: container))
        precondition(!ActionConditions().matches(context: ActionMatchContext(urls: [], isContainer: false)))

        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        let aliased = ActionMatchContext(urls: [alias.appendingPathComponent("readme.MD")], isContainer: false)
        precondition(scoped.matches(context: aliased), "符号链接仍应匹配真实路径")
        let sibling = ActionMatchContext(urls: [URL(fileURLWithPath: directory.path + "-other/readme.MD")], isContainer: false)
        precondition(!scoped.matches(context: sibling), "路径前缀必须匹配目录边界")
    }

    private static func testDefaults(_ defaults: UserDefaults) {
        let configuration = SharedPreferences.configuration(defaults: defaults)
        precondition(configuration.version == AssistantConfiguration.currentVersion)
        precondition(configuration.actions.contains { $0.builtInOperation == .copyPath })
        precondition(configuration.actions.contains { $0.kind == .template })
        precondition(configuration.actions.contains { $0.kind == .terminal })
    }

    private static func testLegacyMigration(_ defaults: UserDefaults) throws {
        clearConfigurationState(defaults)
        defaults.set(
            ["openInTerminal", "copyName", "copyPath", "newTextFile"],
            forKey: "orderedActionIDs"
        )
        defaults.set(["copyName", "newTextFile"], forKey: "enabledActionIDs")
        let legacyApplication = LegacyApplication(
            id: "legacy-editor",
            applicationName: "Editor",
            bundleIdentifier: "com.example.Editor",
            applicationPath: "/Applications/Editor.app",
            menuTitle: "用 Editor 打开",
            isEnabled: true
        )
        defaults.set(try JSONEncoder().encode([legacyApplication]), forKey: "applicationActions")

        let configuration = SharedPreferences.configuration(defaults: defaults)
        precondition(configuration.actions.first?.id == "terminal.system")
        precondition(configuration.actions.first(where: { $0.id == "builtin.copyPath" })?.isEnabled == false)
        precondition(configuration.actions.first(where: { $0.id == "template.text" })?.isEnabled == true)
        precondition(configuration.actions.contains { $0.id == "legacy-editor" && $0.kind == .application })
    }

    private static func testLegacyMigrationEdgeCases(_ defaults: UserDefaults) throws {
        clearConfigurationState(defaults)
        let applicationOnly = LegacyApplication(
            id: "application-only",
            applicationName: "Application Only",
            bundleIdentifier: "com.example.ApplicationOnly",
            applicationPath: "/Applications/Application Only.app",
            menuTitle: "用 Application Only 打开",
            isEnabled: true
        )
        defaults.set(try JSONEncoder().encode([applicationOnly]), forKey: "applicationActions")

        let migratedApplicationOnly = SharedPreferences.configuration(defaults: defaults)
        precondition(migratedApplicationOnly.actions.contains { $0.id == applicationOnly.id })

        clearConfigurationState(defaults)
        defaults.set(["copyPath", "copyName", "newTextFile", "openInTerminal"], forKey: "orderedActionIDs")
        let missingEnabledIDs = SharedPreferences.configuration(defaults: defaults)
        precondition(missingEnabledIDs.actions.allSatisfy(\.isEnabled))

        clearConfigurationState(defaults)
        defaults.set(["copyPath", "copyName", "newTextFile", "openInTerminal"], forKey: "orderedActionIDs")
        defaults.set([String](), forKey: "enabledActionIDs")
        let explicitlyDisabled = SharedPreferences.configuration(defaults: defaults)
        precondition(explicitlyDisabled.actions.allSatisfy { !$0.isEnabled })
    }

    private static func testConditions() {
        let markdown = URL(fileURLWithPath: "/tmp/right-click-test/readme.MD")
        let swift = URL(fileURLWithPath: "/tmp/right-click-test/main.swift")
        let conditions = ActionConditions(
            allowsFiles: true,
            allowsFolders: false,
            allowsContainer: false,
            fileExtensions: [".md", "MD"],
            minimumSelectionCount: 1,
            maximumSelectionCount: 2,
            pathPrefixes: ["/tmp/right-click-test"]
        )
        precondition(conditions.fileExtensions == ["md"])
        precondition(conditions.matches(urls: [markdown], isContainer: false))
        precondition(!conditions.matches(urls: [swift], isContainer: false))
        precondition(!conditions.matches(urls: [markdown, markdown, markdown], isContainer: false))
        precondition(!conditions.matches(urls: [URL(fileURLWithPath: "/other/readme.md")], isContainer: false))

        let rootScoped = ActionConditions(pathPrefixes: ["/"])
        precondition(rootScoped.matches(urls: [markdown], isContainer: false))
        precondition(rootScoped.matches(urls: [URL(fileURLWithPath: "/Users/test/file.txt")], isContainer: false))

        let container = ActionConditions(allowsFiles: false, allowsFolders: false, allowsContainer: true)
        precondition(container.matches(urls: [URL(fileURLWithPath: "/tmp", isDirectory: true)], isContainer: true))
    }

    private static func testConfigurationRoundTrip(_ defaults: UserDefaults) {
        let group = ActionGroup(id: "group", title: "测试")
        let action = ConfiguredAction(
            id: "action",
            kind: .shell,
            title: "运行测试",
            isFavorite: true,
            groupID: group.id,
            script: "echo ok"
        )
        let configuration = AssistantConfiguration(
            actions: [action, action],
            groups: [group, group],
            showsFavoritesAtTopLevel: false
        )
        defaults.set(SharedPreferences.encoded(configuration), forKey: SharedPreferences.configurationKey)

        let restored = SharedPreferences.configuration(defaults: defaults)
        precondition(restored.actions == [action])
        precondition(restored.groups == [group])
        precondition(!restored.showsFavoritesAtTopLevel)
    }

    private static func testV2GroupIconMigration(_ defaults: UserDefaults) throws {
        let legacyFiles = ActionGroup(id: "files", title: "文件", symbolName: "doc.on.doc")
        let customGroup = ActionGroup(id: "custom", title: "自定义", symbolName: "doc.on.doc")
        let migrated = AssistantConfiguration(
            version: 2,
            actions: [],
            groups: [legacyFiles, customGroup]
        ).normalized()

        precondition(migrated.version == AssistantConfiguration.currentVersion)
        precondition(migrated.groups.first(where: { $0.id == "files" })?.symbolName == "folder.fill")
        precondition(migrated.groups.first(where: { $0.id == "custom" })?.symbolName == "doc.on.doc")

        let customizedFiles = AssistantConfiguration(
            version: 2,
            actions: [],
            groups: [ActionGroup(id: "files", title: "文件", symbolName: "star.fill")]
        ).normalized()
        precondition(customizedFiles.groups.first?.symbolName == "star.fill")

        let currentVersionChoice = AssistantConfiguration(
            version: AssistantConfiguration.currentVersion,
            actions: [],
            groups: [legacyFiles]
        ).normalized()
        precondition(currentVersionChoice.groups.first?.symbolName == "doc.on.doc")

        clearConfigurationState(defaults)
        let legacyData = try JSONEncoder().encode(
            AssistantConfiguration(
                version: 2,
                actions: [],
                groups: [legacyFiles]
            )
        )
        defaults.set(legacyData, forKey: SharedPreferences.configurationKey)
        let loaded = SharedPreferences.loadConfiguration(defaults: defaults)
        precondition(loaded.configuration.version == AssistantConfiguration.currentVersion)
        let persistedData = defaults.data(forKey: SharedPreferences.configurationKey)!
        let persisted = try JSONDecoder().decode(AssistantConfiguration.self, from: persistedData)
        precondition(persisted.version == AssistantConfiguration.currentVersion)
        precondition(persisted.groups.first?.symbolName == "folder.fill")
    }

    private static func testConfigurationRecovery(_ defaults: UserDefaults) throws {
        clearConfigurationState(defaults)
        let orphanedBackup = AssistantConfiguration(
            actions: [ConfiguredAction(id: "backup-only", kind: .shell, title: "仅备份", script: "echo backup")],
            groups: []
        )
        let orphanedBackupData = try JSONEncoder().encode(orphanedBackup)
        defaults.set(orphanedBackupData, forKey: SharedPreferences.lastKnownGoodConfigurationKey)
        let restoredMissingPrimary = SharedPreferences.loadConfiguration(defaults: defaults)
        precondition(restoredMissingPrimary.issue == nil)
        precondition(restoredMissingPrimary.recoveredFromLastKnownGood)
        precondition(restoredMissingPrimary.configuration == orphanedBackup.normalized())
        precondition(defaults.data(forKey: SharedPreferences.configurationKey) != nil)

        clearConfigurationState(defaults)
        let unrecoverableData = Data("not-json-without-backup".utf8)
        defaults.set(unrecoverableData, forKey: SharedPreferences.configurationKey)
        let safeFailure = SharedPreferences.loadConfiguration(defaults: defaults)
        precondition(safeFailure.issue == .corruptedData)
        precondition(!safeFailure.recoveredFromLastKnownGood)
        precondition(safeFailure.configuration.actions.isEmpty)
        precondition(defaults.data(forKey: SharedPreferences.configurationKey) == unrecoverableData)
        precondition(defaults.data(forKey: SharedPreferences.configurationRecoveryDataKey) == unrecoverableData)

        clearConfigurationState(defaults)
        let goodConfiguration = AssistantConfiguration(
            actions: [ConfiguredAction(id: "known-good", kind: .shell, title: "已验证", script: "echo ok")],
            groups: []
        )
        let goodData = try JSONEncoder().encode(goodConfiguration)
        defaults.set(goodData, forKey: SharedPreferences.configurationKey)

        let initialLoad = SharedPreferences.loadConfiguration(defaults: defaults)
        precondition(initialLoad.issue == nil)
        precondition(!initialLoad.recoveredFromLastKnownGood)

        let corruptedData = Data("not-json".utf8)
        defaults.set(corruptedData, forKey: SharedPreferences.configurationKey)
        let recoveredCorruption = SharedPreferences.loadConfiguration(defaults: defaults)
        precondition(recoveredCorruption.issue == .corruptedData)
        precondition(recoveredCorruption.recoveredFromLastKnownGood)
        precondition(recoveredCorruption.configuration == goodConfiguration.normalized())
        precondition(defaults.data(forKey: SharedPreferences.configurationKey) == corruptedData)
        precondition(defaults.data(forKey: SharedPreferences.configurationRecoveryDataKey) == corruptedData)
        precondition(defaults.string(forKey: SharedPreferences.configurationLoadIssueKey) == "corruptedData")

        defaults.set(SharedPreferences.encoded(recoveredCorruption.configuration), forKey: SharedPreferences.configurationKey)
        precondition(defaults.data(forKey: SharedPreferences.configurationRecoveryDataKey) == corruptedData)

        let futureVersion = AssistantConfiguration.currentVersion + 1
        let futureData = Data(
            #"{"version":\#(futureVersion),"actions":[{"kind":"futureAction","title":"未来动作"}],"groups":[]}"#.utf8
        )
        defaults.set(futureData, forKey: SharedPreferences.configurationKey)
        let recoveredFuture = SharedPreferences.loadConfiguration(defaults: defaults)
        precondition(recoveredFuture.issue == .unsupportedVersion(futureVersion))
        precondition(recoveredFuture.recoveredFromLastKnownGood)
        precondition(recoveredFuture.configuration == goodConfiguration.normalized())
        precondition(defaults.data(forKey: SharedPreferences.configurationKey) == futureData)
        precondition(defaults.data(forKey: SharedPreferences.configurationRecoveryDataKey) == futureData)
        precondition(defaults.data(forKey: SharedPreferences.previousConfigurationRecoveryDataKey) == corruptedData)
    }

    private static func testForwardCompatibleDecode() throws {
        let data = Data(#"{"kind":"shell","title":"最小脚本","script":"echo ok"}"#.utf8)
        let action = try JSONDecoder().decode(ConfiguredAction.self, from: data)
        precondition(action.isEnabled)
        precondition(!action.isFavorite)
        precondition(action.symbolName == ActionKind.shell.symbolName)
        precondition(action.conditions.allowsContainer)
    }

    private static func testExecutionURL(_ defaults: UserDefaults) {
        let targets = [
            URL(fileURLWithPath: "/tmp/空 格/文件.md"),
            URL(fileURLWithPath: "/tmp/a&b.txt")
        ]
        let createdAt = Date(timeIntervalSince1970: 10_000)
        let url = SharedPreferences.executionURL(
            actionID: "script.test",
            urls: targets,
            isContainer: true,
            defaults: defaults,
            createdAt: createdAt
        )!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        precondition(components.queryItems?.map(\.name) == ["request"])
        precondition(!url.absoluteString.contains("script.test"))
        precondition(!url.absoluteString.contains("target"))

        let restored = SharedPreferences.executionRequest(
            from: url,
            defaults: defaults,
            now: createdAt.addingTimeInterval(1)
        )!
        precondition(restored.actionID == "script.test")
        precondition(restored.urls.map(\.path) == targets.map(\.path))
        precondition(restored.isContainer)
        precondition(SharedPreferences.executionRequest(from: url, defaults: defaults, now: createdAt) == nil)

        let legacyURL = URL(string: "rightclickassistant://execute?action=template.text&target=/tmp")!
        precondition(SharedPreferences.executionRequest(from: legacyURL, defaults: defaults, now: createdAt) == nil)

        let expiredURL = SharedPreferences.executionURL(
            actionID: "script.expired",
            urls: targets,
            isContainer: false,
            defaults: defaults,
            createdAt: createdAt.addingTimeInterval(-60)
        )!
        precondition(SharedPreferences.executionRequest(from: expiredURL, defaults: defaults, now: createdAt) == nil)
    }

    private static func clearConfigurationState(_ defaults: UserDefaults) {
        [
            SharedPreferences.configurationKey,
            SharedPreferences.lastKnownGoodConfigurationKey,
            SharedPreferences.configurationRecoveryDataKey,
            SharedPreferences.previousConfigurationRecoveryDataKey,
            SharedPreferences.configurationLoadIssueKey,
            "enabledActionIDs",
            "orderedActionIDs",
            "applicationActions"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    private struct LegacyApplication: Codable {
        let id: String
        let applicationName: String
        let bundleIdentifier: String?
        let applicationPath: String
        let menuTitle: String
        let isEnabled: Bool
    }
}
