import Foundation

enum TemplatePreset: String, CaseIterable, Identifiable {
    case plainText, markdown, json, yaml, shell, python, html

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: L10n.tr("纯文本")
        case .markdown: "Markdown"
        case .json: "JSON"
        case .yaml: "YAML"
        case .shell: "Shell"
        case .python: "Python"
        case .html: "HTML"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .markdown: "md"
        case .json: "json"
        case .yaml: "yaml"
        case .shell: "sh"
        case .python: "py"
        case .html: "html"
        }
    }

    var content: String {
        switch self {
        case .plainText: ""
        case .markdown: "# Title\n\n"
        case .json: "{\n  \"name\": \"\"\n}\n"
        case .yaml: "name: \"\"\n"
        case .shell: "#!/bin/zsh\nset -euo pipefail\n\n"
        case .python: "#!/usr/bin/env python3\n\n\ndef main():\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n"
        case .html: "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>Document</title>\n</head>\n<body>\n\n</body>\n</html>\n"
        }
    }

    func makeAction(groups: [ActionGroup] = []) -> ConfiguredAction {
        ConfiguredAction(
            kind: .template,
            title: self == .plainText ? "新建文本文件" : "新建 \(title) 文件",
            groupID: groups.first(where: { $0.id == "files" })?.id,
            conditions: ActionConditions(allowsFiles: false, allowsFolders: true, allowsContainer: true),
            templateExtension: fileExtension,
            templateContent: content
        )
    }
}
