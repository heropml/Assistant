import Foundation

@main
struct LocalizationSmoke {
    static func main() throws {
        for (chinese, english) in L10n.english {
            precondition(chinese.components(separatedBy: "%@").count == english.components(separatedBy: "%@").count,
                         "翻译占位符不一致：\(chinese)")
            let count = chinese.components(separatedBy: "%@").count - 1
            let arguments = (0..<count).map { "value-\($0)" }
            let rendered = L10n.text(chinese, arguments: arguments, language: .english)
            precondition(!rendered.contains("%@"), "未替换的占位符")
        }
        precondition(L10n.text("右键助手", language: .english) == "Right-Click Assistant")
        precondition(L10n.text("右键助手", language: .simplifiedChinese) == "右键助手")
        let userInput = "客户 %@ 100% 中文"
        precondition(L10n.text("已完成：%@", arguments: [userInput], language: .english) == "Completed: \(userInput)")
        precondition(L10n.text("正在下载 %@%", arguments: ["50"], language: .english) == "Downloading 50%")

        let configuration = AssistantConfiguration.defaultValue
        let before = try JSONEncoder().encode(configuration)
        let titles = configuration.actions.map { $0.displayTitle(language: .english) }
        precondition(titles == ["Copy Path", "Copy Filename", "Cut", "Paste Cut Items", "New Text File", "Open in Terminal"])
        precondition(configuration.groups.map { $0.displayTitle(language: .english) } == ["Files", "Open With"])
        precondition(configuration.actions.map { $0.displayTitle(language: .simplifiedChinese) } == configuration.actions.map(\.title))
        let after = try JSONEncoder().encode(configuration)
        let decodedBefore = try JSONDecoder().decode(AssistantConfiguration.self, from: before)
        let decodedAfter = try JSONDecoder().decode(AssistantConfiguration.self, from: after)
        precondition(decodedBefore == decodedAfter, "显示语言不能修改配置")

        var custom = configuration.actions[0]
        custom.title = "复制我的路径"
        precondition(custom.displayTitle(language: .english) == custom.title)
        let script = ConfiguredAction(kind: .shell, title: "复制路径", script: "echo 中文")
        precondition(script.displayTitle(language: .english) == "复制路径", "自定义脚本名称不应按内置动作翻译")
        let customGroup = ActionGroup(id: "custom", title: "文件")
        precondition(customGroup.displayTitle(language: .english) == "文件")
        precondition(ActionGroup(id: "custom2", title: "新分组").displayTitle(language: .english) == "新分组")
        print("中英文测试通过（文案、占位符、默认名称、自定义名称和配置不变）")
    }
}
