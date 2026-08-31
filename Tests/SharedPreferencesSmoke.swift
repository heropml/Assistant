import Foundation

@main
struct SharedPreferencesSmoke {
    static func main() {
        let suiteName = "com.local.RightClickAssistant.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("无法创建测试偏好域")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            ["openInTerminal", "openInTerminal", "unknown", "copyName"],
            forKey: SharedPreferences.orderedActionIDsKey
        )

        precondition(
            SharedPreferences.orderedActions(defaults: defaults) == [
                .openInTerminal, .copyName, .copyPath, .newTextFile
            ],
            "动作排序恢复失败"
        )

        defaults.set(
            ["copyName", "newTextFile"],
            forKey: SharedPreferences.enabledActionIDsKey
        )

        precondition(
            SharedPreferences.enabledActions(defaults: defaults) == [.copyName, .newTextFile],
            "动作启停过滤失败"
        )

        let application = ApplicationAction(
            id: "test-app",
            applicationName: "Test Editor",
            bundleIdentifier: "com.example.TestEditor",
            applicationPath: "/Applications/Test Editor.app",
            menuTitle: "用测试编辑器打开"
        )
        defaults.set(try! JSONEncoder().encode([application, application]),
                     forKey: SharedPreferences.applicationActionsKey)

        precondition(
            SharedPreferences.applicationActions(defaults: defaults) == [application],
            "自定义应用配置恢复失败"
        )

        print("共享配置测试通过")
    }
}
