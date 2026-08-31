import Foundation

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
        testConditions()
        testConfigurationRoundTrip(defaults)
        try testForwardCompatibleDecode()
        testExecutionURL()

        print("V2 共享配置测试通过")
    }

    private static func testDefaults(_ defaults: UserDefaults) {
        let configuration = SharedPreferences.configuration(defaults: defaults)
        precondition(configuration.version == AssistantConfiguration.currentVersion)
        precondition(configuration.actions.contains { $0.builtInOperation == .copyPath })
        precondition(configuration.actions.contains { $0.kind == .template })
        precondition(configuration.actions.contains { $0.kind == .terminal })
    }

    private static func testLegacyMigration(_ defaults: UserDefaults) throws {
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

    private static func testForwardCompatibleDecode() throws {
        let data = Data(#"{"kind":"shell","title":"最小脚本","script":"echo ok"}"#.utf8)
        let action = try JSONDecoder().decode(ConfiguredAction.self, from: data)
        precondition(action.isEnabled)
        precondition(!action.isFavorite)
        precondition(action.symbolName == ActionKind.shell.symbolName)
        precondition(action.conditions.allowsContainer)
    }

    private static func testExecutionURL() {
        let targets = [
            URL(fileURLWithPath: "/tmp/空 格/文件.md"),
            URL(fileURLWithPath: "/tmp/a&b.txt")
        ]
        let url = SharedPreferences.executionURL(actionID: "script.test", urls: targets)!
        let restored = SharedPreferences.executionRequest(from: url)!
        precondition(restored.actionID == "script.test")
        precondition(restored.urls.map(\.path) == targets.map(\.path))
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
