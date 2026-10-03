import Foundation

@main
struct TemplatePresetSmoke {
    static func main() throws {
        let expectedNames: [TemplatePreset: (String, String)] = [
            .plainText: ("新建文本文件", "New Text File"),
            .markdown: ("新建 Markdown 文件", "New Markdown File"),
            .json: ("新建 JSON 文件", "New JSON File"),
            .yaml: ("新建 YAML 文件", "New YAML File"),
            .shell: ("新建 Shell 文件", "New Shell File"),
            .python: ("新建 Python 文件", "New Python File"),
            .html: ("新建 HTML 文件", "New HTML File")
        ]
        let filesGroup = ActionGroup(id: "files", title: "我的文件")
        for preset in TemplatePreset.allCases {
            let action = preset.makeAction(groups: [filesGroup])
            let names = expectedNames[preset]!
            precondition(action.displayTitle(language: .simplifiedChinese) == names.0)
            precondition(action.displayTitle(language: .english) == names.1)
            precondition(action.groupID == filesGroup.id)
            precondition(preset.makeAction().groupID == nil)
            precondition(preset.makeAction(groups: [ActionGroup(id: "custom", title: "文件")]).groupID == nil)
            let configuration = AssistantConfiguration(actions: [action], groups: [filesGroup])
            let imported = try ConfigurationTransfer.decode(ConfigurationTransfer.encode(configuration))
            precondition(imported.actions.first?.groupID == filesGroup.id)
            var renamed = action
            renamed.title = "我的模板"
            precondition(renamed.displayTitle(language: .english) == "我的模板")
        }
        let expectedFileNames: [TemplatePreset: (String, String)] = [
            .plainText: ("文本文件", "Text File"),
            .markdown: ("Markdown 文件", "Markdown File"),
            .json: ("JSON 文件", "JSON File"),
            .yaml: ("YAML 文件", "YAML File"),
            .shell: ("Shell 文件", "Shell File"),
            .python: ("Python 文件", "Python File"),
            .html: ("HTML 文件", "HTML File")
        ]
        for preset in TemplatePreset.allCases {
            let action = preset.makeAction()
            let names = expectedFileNames[preset]!
            precondition(action.templateFileBaseName(language: .simplifiedChinese) == names.0)
            precondition(action.templateFileBaseName(language: .english) == names.1, "英文界面不应生成中文文件名")
        }
        for (title, chinese, english) in [
            ("新建文稿", "文稿", "文稿"),
            ("New Notes", "Notes", "Notes"),
            ("我的模板", "我的模板", "我的模板"),
            ("新建文件", "文件", "File"),
            ("新建", "", ""),
            ("周报新建", "周报", "周报")
        ] {
            let action = ConfiguredAction(kind: .template, title: title, templateExtension: "txt")
            precondition(action.templateFileBaseName(language: .simplifiedChinese) == chinese, "中文文件名错误：\(title)")
            precondition(action.templateFileBaseName(language: .english) == english, "英文文件名错误：\(title)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistantTemplates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for preset in TemplatePreset.allCases {
            let action = preset.makeAction()
            precondition(action.kind == .template && action.script == nil)
            precondition(!action.conditions.allowsFiles && action.conditions.allowsContainer)
            precondition(action.normalizedTemplateExtension == preset.fileExtension)
            let restored = try JSONDecoder().decode(ConfiguredAction.self, from: JSONEncoder().encode(action))
            precondition(restored == action)
            try HostActionExecutor.execute(action: action, urls: [directory], revealCreatedFiles: false)
            try HostActionExecutor.execute(action: action, urls: [directory], revealCreatedFiles: false)
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(files.count == TemplatePreset.allCases.count * 2)
        for preset in TemplatePreset.allCases {
            let matches = files.filter { $0.pathExtension == preset.fileExtension }
            precondition(matches.count == 2)
            for file in matches {
                let data = try Data(contentsOf: file)
                precondition(data == Data(preset.content.utf8))
                if preset == .json { _ = try JSONSerialization.jsonObject(with: data) }
            }
        }
        print("模板预设测试通过（中英文动作名、分组兼容、配置往返、实际创建、内容和重名保护）")
    }
}
