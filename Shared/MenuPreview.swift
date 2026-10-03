import Foundation

enum MenuPreviewExclusion: Equatable, Sendable {
    case disabled
    case noSelection
    case containerNotAllowed
    case filesNotAllowed
    case foldersNotAllowed
    case extensionMismatch([String])
    case tooFewItems(Int)
    case tooManyItems(Int)
    case pathMismatch([String])

    var description: String {
        switch self {
        case .disabled:
            L10n.tr("动作已禁用")
        case .noSelection:
            L10n.tr("尚未选择样例")
        case .containerNotAllowed:
            L10n.tr("不在文件夹空白处显示")
        case .filesNotAllowed:
            L10n.tr("不支持所选文件")
        case .foldersNotAllowed:
            L10n.tr("不支持所选文件夹")
        case .extensionMismatch(let extensions):
            L10n.tr("文件扩展名需为：%@", extensions.joined(separator: ", "))
        case .tooFewItems(let count):
            L10n.tr("至少需要选择 %@ 个项目", String(count))
        case .tooManyItems(let count):
            L10n.tr("最多允许选择 %@ 个项目", String(count))
        case .pathMismatch(let prefixes):
            L10n.tr("项目需位于以下目录内：%@", prefixes.joined(separator: ", "))
        }
    }
}

struct MenuPreviewSnapshot {
    struct Section: Identifiable {
        let group: ActionGroup?
        let actions: [ConfiguredAction]
        var id: String { group.map { "group:\($0.id)" } ?? "ungrouped" }
    }

    struct HiddenAction: Identifiable {
        let action: ConfiguredAction
        let reasons: [MenuPreviewExclusion]
        var id: String { action.id }
    }

    let favorites: [ConfiguredAction]
    let sections: [Section]
    let hiddenActions: [HiddenAction]

    var visibleCount: Int {
        favorites.count + sections.reduce(0) { $0 + $1.actions.count }
    }

    init(configuration: AssistantConfiguration, urls: [URL], isContainer: Bool) {
        let context = ActionMatchContext(urls: urls, isContainer: isContainer)
        // Keep visibility and the top-level favorites identical to FinderSync.
        let applicable = configuration.actions.filter {
            $0.isEnabled && $0.conditions.matches(context: context)
        }
        favorites = configuration.showsFavoritesAtTopLevel
            ? Array(applicable.filter(\.isFavorite).prefix(AssistantConfiguration.maximumTopLevelFavorites)) : []
        let favoriteIDs = Set(favorites.map(\.id))
        let remaining = applicable.filter { !favoriteIDs.contains($0.id) }
        var sections: [Section] = configuration.groups.compactMap { group in
            let actions = remaining.filter { $0.groupID == group.id }
            return actions.isEmpty ? nil : Section(group: group, actions: actions)
        }
        let ungrouped = remaining.filter { $0.groupID == nil }
        if !ungrouped.isEmpty {
            sections.append(Section(group: nil, actions: ungrouped))
        }
        self.sections = sections
        let applicableIDs = Set(applicable.map(\.id))
        hiddenActions = configuration.actions.compactMap { action in
            guard !applicableIDs.contains(action.id) else { return nil }
            return HiddenAction(action: action, reasons: Self.exclusions(for: action, context: context))
        }
    }

    private static func exclusions(for action: ConfiguredAction, context: ActionMatchContext) -> [MenuPreviewExclusion] {
        guard action.isEnabled else { return [.disabled] }
        guard !context.urls.isEmpty else { return [.noSelection] }
        let conditions = action.conditions
        var reasons: [MenuPreviewExclusion] = []

        // Evaluate each restriction through the same matcher instead of duplicating
        // extension/path matching or its special rules for folder background menus.
        if !ActionConditions(allowsContainer: conditions.allowsContainer).matches(context: context) {
            reasons.append(.containerNotAllowed)
        }
        if !ActionConditions(allowsFiles: conditions.allowsFiles).matches(context: context) {
            reasons.append(.filesNotAllowed)
        }
        if !ActionConditions(allowsFolders: conditions.allowsFolders).matches(context: context) {
            reasons.append(.foldersNotAllowed)
        }
        if !ActionConditions(fileExtensions: conditions.fileExtensions).matches(context: context) {
            reasons.append(.extensionMismatch(conditions.fileExtensions))
        }
        if !ActionConditions(minimumSelectionCount: conditions.minimumSelectionCount).matches(context: context) {
            reasons.append(.tooFewItems(conditions.minimumSelectionCount))
        }
        if !ActionConditions(maximumSelectionCount: conditions.maximumSelectionCount).matches(context: context),
           let maximum = conditions.maximumSelectionCount {
            reasons.append(.tooManyItems(maximum))
        }
        if !ActionConditions(pathPrefixes: conditions.pathPrefixes).matches(context: context) {
            reasons.append(.pathMismatch(conditions.pathPrefixes))
        }
        return reasons
    }
}
