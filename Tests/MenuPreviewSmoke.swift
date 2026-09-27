import Foundation

@main
struct MenuPreviewSmoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AssistantMenuPreview-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("samples")
        let sibling = root.appendingPathComponent("samples-other")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let markdown = directory.appendingPathComponent("Readme.MD")
        let text = directory.appendingPathComponent("notes.txt")
        let outside = sibling.appendingPathComponent("other.md")
        for url in [markdown, text, outside] { try Data().write(to: url) }
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)

        testMenuOrdering(markdown)
        testExclusions(directory: directory, markdown: markdown, text: text, outside: outside, alias: alias)
        testVisibilityMatchesFinder(urls: [markdown, text, directory])
        print("菜单预览测试通过（收藏上限、分组顺序、隐藏原因及真实匹配规则一致性）")
    }

    private static func testMenuOrdering(_ file: URL) {
        let group = ActionGroup(id: "files", title: "文件")
        let actions = (0..<8).map {
            ConfiguredAction(id: "action-\($0)", kind: .shell, title: "Action \($0)", isFavorite: true, groupID: group.id)
        } + [ConfiguredAction(id: "ungrouped", kind: .shell, title: "Ungrouped")]
        var configuration = AssistantConfiguration(actions: actions, groups: [group])
        var preview = MenuPreviewSnapshot(configuration: configuration, urls: [file], isContainer: false)
        precondition(preview.favorites.map(\.id) == Array(actions.prefix(6)).map(\.id))
        precondition(preview.sections.count == 2)
        precondition(preview.sections[0].group == group)
        precondition(preview.sections[0].actions.map(\.id) == ["action-6", "action-7"])
        precondition(preview.sections[1].group == nil)
        precondition(preview.sections[1].actions.map(\.id) == ["ungrouped"])
        precondition(preview.visibleCount == 9 && preview.hiddenActions.isEmpty)

        configuration.showsFavoritesAtTopLevel = false
        preview = MenuPreviewSnapshot(configuration: configuration, urls: [file], isContainer: false)
        precondition(preview.favorites.isEmpty)
        precondition(preview.sections[0].actions.count == 8)
    }

    private static func testExclusions(directory: URL, markdown: URL, text: URL, outside: URL, alias: URL) {
        var action = ConfiguredAction(kind: .shell, title: "Restricted", conditions: ActionConditions(
            allowsFiles: false,
            allowsFolders: false,
            allowsContainer: false,
            fileExtensions: ["md"],
            minimumSelectionCount: 2,
            maximumSelectionCount: 2,
            pathPrefixes: [directory.path]
        ))
        func preview(_ urls: [URL], container: Bool = false) -> MenuPreviewSnapshot {
            MenuPreviewSnapshot(configuration: AssistantConfiguration(actions: [action], groups: []), urls: urls, isContainer: container)
        }
        precondition(preview([text]).hiddenActions[0].reasons == [.filesNotAllowed, .extensionMismatch(["md"]), .tooFewItems(2)])
        precondition(preview([directory]).hiddenActions[0].reasons == [.foldersNotAllowed, .tooFewItems(2)])
        precondition(preview([directory], container: true).hiddenActions[0].reasons == [.containerNotAllowed])
        precondition(preview([outside]).hiddenActions[0].reasons.contains(.pathMismatch([directory.path])))
        precondition(preview([markdown, text, directory]).hiddenActions[0].reasons.contains(.tooManyItems(2)))

        action.isEnabled = false
        precondition(preview([text]).hiddenActions[0].reasons == [.disabled])
        action.isEnabled = true
        precondition(preview([]).hiddenActions[0].reasons == [.noSelection])

        action.conditions = ActionConditions(fileExtensions: ["md"], pathPrefixes: [directory.path])
        precondition(preview([markdown]).visibleCount == 1, "扩展名匹配应忽略大小写")
        precondition(preview([alias.appendingPathComponent("Readme.MD")]).visibleCount == 1, "预览需沿用真实路径解析")
        precondition(preview([outside]).hiddenActions[0].reasons == [.pathMismatch([directory.path])], "相同前缀的兄弟目录不匹配")
        precondition(preview([directory], container: true).visibleCount == 1, "文件夹空白处忽略文件扩展名")
    }

    private static func testVisibilityMatchesFinder(urls: [URL]) {
        let conditionSets = [
            ActionConditions(),
            ActionConditions(allowsFiles: false),
            ActionConditions(allowsFolders: false),
            ActionConditions(allowsContainer: false),
            ActionConditions(fileExtensions: ["txt"]),
            ActionConditions(minimumSelectionCount: 2),
            ActionConditions(maximumSelectionCount: 1),
            ActionConditions(pathPrefixes: ["/definitely-not-the-sample-directory"])
        ]
        let actions = conditionSets.enumerated().map { index, conditions in
            ConfiguredAction(id: "condition-\(index)", kind: .shell, title: "Condition \(index)", conditions: conditions)
        }
        let configuration = AssistantConfiguration(actions: actions, groups: [])
        for samples in [urls, [urls[0]], [urls[2]], []] {
            for container in [false, true] {
                let context = ActionMatchContext(urls: samples, isContainer: container)
                let applicable = actions.filter { $0.isEnabled && $0.conditions.matches(context: context) }
                let preview = MenuPreviewSnapshot(configuration: configuration, urls: samples, isContainer: container)
                precondition(preview.sections.flatMap(\.actions).map(\.id) == applicable.map(\.id))
                precondition(preview.hiddenActions.allSatisfy { !$0.reasons.isEmpty })
                precondition(preview.visibleCount + preview.hiddenActions.count == actions.count)
            }
        }
    }
}
