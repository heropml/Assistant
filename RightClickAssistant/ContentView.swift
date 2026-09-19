import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var language = LanguageStore.shared
    @EnvironmentObject private var store: ActionStore
    @Environment(\.openSettings) private var openSettings
    @State private var editingAction: ConfiguredAction?
    @State private var groupEditor: GroupEditorContext?
    @State private var groupPendingDeletion: ActionGroup?
    @State private var isShowingGroupDeleteConfirmation = false
    @State private var searchText = ""
    @State private var showsExecutionHistory = false
    @State private var transferError: String?
    @State private var showsUpdate = false
    @StateObject private var updater = UpdateManager()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let issue = store.configurationLoadIssue {
                configurationWarning(
                    issue,
                    recoveredFromBackup: store.recoveredConfigurationFromLastKnownGood
                )
                Divider()
            }
            toolbar
            Divider()
            if !store.executions.isEmpty {
                executionStatus
                Divider()
            }
            actionList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showsUpdate) { UpdateView(updater: updater) }
        .sheet(item: $editingAction) { action in
            ActionEditor(action: action, groups: store.groups) { store.upsert($0) }
        }
        .sheet(item: $groupEditor) { context in
            GroupEditor(group: context.group, isNew: context.isNew) { group in
                if context.isNew {
                    store.addGroup(title: group.title, symbolName: group.symbolName)
                } else {
                    store.updateGroup(group)
                }
            }
        }
        .confirmationDialog(
            L10n.tr("删除分组“%@”？", String(describing: groupPendingDeletion?.localizedTitle ?? "")),
            isPresented: $isShowingGroupDeleteConfirmation
        ) {
            Button(L10n.tr("删除分组"), role: .destructive) {
                guard let group = groupPendingDeletion else { return }
                store.removeGroup(group)
                groupPendingDeletion = nil
            }
            Button(L10n.tr("取消"), role: .cancel) { groupPendingDeletion = nil }
        } message: {
            Text(L10n.tr("分组内的动作会保留，并移到未分组。"))
        }
        .alert(L10n.tr("配置操作失败"), isPresented: Binding(
            get: { transferError != nil },
            set: { if !$0 { transferError = nil } }
        )) {
            Button(L10n.tr("好"), role: .cancel) { transferError = nil }
        } message: {
            Text(transferError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 64, height: 64)
                .shadow(color: .indigo.opacity(0.22), radius: 10, y: 5)
                .accessibilityLabel(L10n.tr("右键助手"))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("右键助手"))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(L10n.tr("一套动作栈，按当前文件和目录自动显示"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Label(L10n.tr("%@ 项启用 · %@ 项直达", String(describing: store.enabledCount), String(describing: store.favoriteCount)), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                HStack(spacing: 12) {
                    Menu {
                        Picker(L10n.tr("语言"), selection: $language.selection) {
                            ForEach(AppLanguage.allCases) { choice in
                                Text(choice.nativeName).tag(choice)
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(L10n.tr("界面语言"))
                    Button(L10n.tr("扩展设置…")) { openSettings() }
                        .buttonStyle(.link)
                    Menu {
                        Button(L10n.tr("导出配置…"), systemImage: "square.and.arrow.up") { exportConfiguration() }
                        Button(L10n.tr("导入配置…"), systemImage: "square.and.arrow.down") { importConfiguration() }
                    } label: {
                        Label(L10n.tr("配置备份"), systemImage: "externaldrive")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.tr("搜索动作、类型或分组"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(width: 260, height: 30)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            Toggle(L10n.tr("收藏显示在一级菜单"), isOn: Binding(
                get: { store.configuration.showsFavoritesAtTopLevel },
                set: { store.setShowsFavoritesAtTopLevel($0) }
            ))
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                groupEditor = GroupEditorContext(group: ActionGroup(title: L10n.tr("新分组")), isNew: true)
            } label: {
                Label(L10n.tr("新建分组"), systemImage: "folder.badge.plus")
            }

            addActionMenu
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var executionStatus: some View {
        DisclosureGroup(isExpanded: $showsExecutionHistory) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.executions) { execution in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(execution.summary)
                                Spacer()
                                Text(execution.startedAt, style: .time)
                                    .foregroundStyle(.secondary)
                            }
                            if case .failed(let message) = execution.outcome {
                                Text(message)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .font(.callout)
                .padding(.top, 8)
            }
            .frame(maxHeight: 180)
        } label: {
            HStack(spacing: 8) {
                if store.runningExecutionCount > 0 {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("正在执行 %@ 个动作", String(describing: store.runningExecutionCount)))
                } else {
                    Text(store.executions.first?.summary ?? L10n.tr("执行记录"))
                }
                Spacer()
                Text(L10n.tr("本次运行记录")).foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L10n.tr("右键助手配置.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigurationTransfer.encode(store.configuration).write(to: url, options: .atomic)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let configuration = try ConfigurationTransfer.decode(Data(contentsOf: url))
            let scripts = configuration.actions.filter { $0.kind == .shell || $0.kind == .appleScript }.count
            let alert = NSAlert()
            alert.messageText = L10n.tr("导入并替换当前配置？")
            alert.informativeText = L10n.tr("文件：%@\n包含 %@ 个动作、%@ 个分组，其中 %@ 个脚本动作。\n\n将替换当前的 %@ 个动作和 %@ 个分组。需要保留当前配置时，请先取消并导出。导入本身不会执行任何动作。", String(describing: url.lastPathComponent), String(describing: configuration.actions.count), String(describing: configuration.groups.count), String(describing: scripts), String(describing: store.actions.count), String(describing: store.groups.count))
            alert.addButton(withTitle: L10n.tr("导入并替换"))
            alert.addButton(withTitle: L10n.tr("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            store.importConfiguration(configuration)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func configurationWarning(
        _ issue: ConfigurationLoadIssue,
        recoveredFromBackup: Bool
    ) -> some View {
        let message: String = switch issue {
        case .corruptedData:
            recoveredFromBackup
                ? L10n.tr("配置数据损坏，已使用最近一次有效配置；原始数据已保留用于恢复。")
                : L10n.tr("配置数据损坏且没有有效备份，已暂停全部动作；原始数据已保留用于恢复。")
        case let .unsupportedVersion(version):
            recoveredFromBackup
                ? L10n.tr("配置来自较新的版本（v%@），当前版本未覆盖它；已使用最近一次有效配置。", String(describing: version))
                : L10n.tr("配置来自较新的版本（v%@）且没有兼容备份，已暂停全部动作以避免覆盖。", String(describing: version))
        }
        return Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.08))
    }

    private var addActionMenu: some View {
        Menu {
            Menu(L10n.tr("基础动作")) {
                Button(L10n.tr("复制路径")) { editBuiltIn(.copyPath) }
                Button(L10n.tr("复制文件名")) { editBuiltIn(.copyName) }
                Button(L10n.tr("剪切")) { editBuiltIn(.cut) }
                Button(L10n.tr("粘贴已剪切项目")) { editBuiltIn(.paste) }
            }
            Divider()
            Button(L10n.tr("应用…"), systemImage: "app") { chooseApplication(kind: .application) }
            Button(L10n.tr("终端…"), systemImage: "apple.terminal") { chooseApplication(kind: .terminal) }
            Button(L10n.tr("常用目录…"), systemImage: "folder") { chooseDirectory() }
            Divider()
            Button(L10n.tr("文件模板"), systemImage: "doc.badge.plus") { editingAction = store.draft(for: .template) }
            Button(L10n.tr("Shell 脚本"), systemImage: "chevron.left.forwardslash.chevron.right") { editingAction = store.draft(for: .shell) }
            Button("AppleScript", systemImage: "applescript") { editingAction = store.draft(for: .appleScript) }
        } label: {
            Label(L10n.tr("添加动作"), systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var actionList: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                groupStrip
                VStack(spacing: 9) {
                    HStack {
                        Text(L10n.tr("动作栈"))
                            .font(.headline)
                        Text(isSearching ? L10n.tr("清空搜索后可调整顺序") : L10n.tr("拖动任意动作可跨类型排序"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.tr("%@ 项", String(describing: filteredActions.count)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    if filteredActions.isEmpty {
                        ContentUnavailableView(
                            L10n.tr("没有匹配的动作"),
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(L10n.tr("更换搜索词，或从右上角添加新动作。"))
                        )
                        .frame(minHeight: 220)
                    } else {
                        ForEach(filteredActions) { action in
                            ActionRow(
                                action: action,
                                groupTitle: groupTitle(for: action),
                                allowsReordering: !isSearching,
                                onEdit: { editingAction = action },
                                onDropAction: { sourceID in store.move(actionID: sourceID, before: action.id) }
                            )
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var groupStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.tr("菜单分组"))
                    .font(.headline)
                Spacer()
                Text(L10n.tr("拖动分组排序；未分组动作固定显示在最后"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.groups) { group in
                        Menu {
                            Button(L10n.tr("向前移动"), systemImage: "arrow.left") {
                                store.moveGroup(group, by: -1)
                            }
                            .disabled(!store.canMoveGroup(group, by: -1))
                            Button(L10n.tr("向后移动"), systemImage: "arrow.right") {
                                store.moveGroup(group, by: 1)
                            }
                            .disabled(!store.canMoveGroup(group, by: 1))
                            Divider()
                            Button(L10n.tr("编辑")) {
                                groupEditor = GroupEditorContext(group: group, isNew: false)
                            }
                            Divider()
                            Button(L10n.tr("删除分组"), role: .destructive) {
                                groupPendingDeletion = group
                                isShowingGroupDeleteConfirmation = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                Label(group.localizedTitle, systemImage: group.symbolName)
                            }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.blue.opacity(0.08), in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .draggable(group.id)
                        .dropDestination(for: String.self) { identifiers, _ in
                            guard let identifier = identifiers.first else { return false }
                            store.moveGroup(groupID: identifier, before: group.id)
                            return true
                        }
                        .help(L10n.tr("拖动调整分组顺序，或点击选择前后移动"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(L10n.tr("修改会即时写入 Finder 配置；脚本、模板与文件移动由右键助手主程序执行。"))
            Spacer()
            Text("v\(AppVersion.current)").monospacedDigit().fixedSize()
            Button(L10n.tr("检查更新")) {
                store.keepRunning()
                showsUpdate = true
            }
            .buttonStyle(.link)
            .fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 13)
        .background(.bar)
    }

    private var filteredActions: [ConfiguredAction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.actions }
        return store.actions.filter { action in
            action.localizedTitle.lowercased().contains(query)
                || action.kind.title.lowercased().contains(query)
                || groupTitle(for: action).lowercased().contains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func groupTitle(for action: ConfiguredAction) -> String {
        guard let groupID = action.groupID else { return L10n.tr("未分组") }
        return store.groups.first(where: { $0.id == groupID })?.localizedTitle ?? L10n.tr("未分组")
    }

    private func editBuiltIn(_ operation: BuiltInOperation) {
        let values: (String, String, ActionConditions)
        switch operation {
        case .copyPath:
            values = (L10n.tr("复制路径"), "point.topleft.down.to.point.bottomright.curvepath", ActionConditions())
        case .copyName:
            values = (L10n.tr("复制文件名"), "doc.on.doc", ActionConditions())
        case .cut:
            values = (L10n.tr("剪切"), "scissors", ActionConditions(allowsContainer: false))
        case .paste:
            values = (
                L10n.tr("粘贴已剪切项目"),
                "doc.on.clipboard",
                ActionConditions(allowsFiles: false, allowsFolders: true, allowsContainer: true)
            )
        }
        editingAction = ConfiguredAction(
            kind: .builtIn,
            title: values.0,
            symbolName: values.1,
            conditions: values.2,
            builtInOperation: operation
        )
    }

    private func chooseApplication(kind: ActionKind) {
        let panel = NSOpenPanel()
        panel.title = kind == .terminal ? L10n.tr("选择终端应用") : L10n.tr("选择打开文件的应用")
        panel.prompt = L10n.tr("选择")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editingAction = store.action(fromApplicationURL: url, kind: kind)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择常用目录")
        panel.prompt = L10n.tr("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editingAction = store.action(fromDirectoryURL: url)
    }
}

private struct ActionRow: View {
    @ObservedObject private var language = LanguageStore.shared
    @EnvironmentObject private var store: ActionStore
    let action: ConfiguredAction
    let groupTitle: String
    let allowsReordering: Bool
    let onEdit: () -> Void
    let onDropAction: (String) -> Void
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .help(L10n.tr("拖动排序"))

            actionIcon
                .frame(width: 38, height: 38)
                .background(kindColor.opacity(action.isEnabled ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(action.localizedTitle)
                        .font(.body.weight(.medium))
                    Text(action.kind.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(kindColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(kindColor.opacity(0.09), in: Capsule())
                    if action.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .help(L10n.tr("一级菜单直达"))
                    }
                }
                Text("\(groupTitle) · \(action.detail) · \(contextSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button {
                store.setFavorite(!action.isFavorite, for: action)
            } label: {
                Image(systemName: action.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(action.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(action.isFavorite ? L10n.tr("取消一级菜单直达") : L10n.tr("添加到一级菜单"))
            .accessibilityLabel(action.isFavorite ? L10n.tr("取消“%@”一级菜单直达", String(describing: action.localizedTitle)) : L10n.tr("将“%@”添加到一级菜单", String(describing: action.localizedTitle)))

            HStack(spacing: 2) {
                moveButton("chevron.up", offset: -1)
                moveButton("chevron.down", offset: 1)
            }
            .buttonStyle(.borderless)

            Menu {
                Button(L10n.tr("编辑"), systemImage: "slider.horizontal.3", action: onEdit)
                Divider()
                Button(L10n.tr("删除"), systemImage: "trash", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(L10n.tr("“%@”更多操作", String(describing: action.localizedTitle)))

            Toggle("", isOn: Binding(
                get: { action.isEnabled },
                set: { store.setEnabled($0, for: action) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(L10n.tr("启用“%@”", String(describing: action.localizedTitle)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
        .draggable(action.id)
        .dropDestination(for: String.self) { identifiers, _ in
            guard allowsReordering, let identifier = identifiers.first else { return false }
            onDropAction(identifier)
            return true
        }
        .confirmationDialog(L10n.tr("删除动作“%@”？", String(describing: action.localizedTitle)), isPresented: $isShowingDeleteConfirmation) {
            Button(L10n.tr("删除"), role: .destructive) { store.remove(action) }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: {
            Text(L10n.tr("此操作会立即写入 Finder 配置。"))
        }
    }

    @ViewBuilder
    private var actionIcon: some View {
        if (action.kind == .application || action.kind == .terminal),
           let applicationURL = action.installedApplicationURL() {
            Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                .resizable()
                .scaledToFit()
                .padding(6)
        } else {
            Image(systemName: action.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(action.isEnabled ? kindColor : .secondary)
        }
    }

    private var kindColor: Color {
        switch action.kind {
        case .builtIn: .blue
        case .application: .purple
        case .terminal: .green
        case .directory: .orange
        case .template: .cyan
        case .shell: .mint
        case .appleScript: .pink
        }
    }

    private var contextSummary: String {
        var parts: [String] = []
        if action.conditions.allowsFiles { parts.append(L10n.tr("文件")) }
        if action.conditions.allowsFolders { parts.append(L10n.tr("文件夹")) }
        if action.conditions.allowsContainer { parts.append(L10n.tr("空白处")) }
        if !action.conditions.fileExtensions.isEmpty {
            parts.append(action.conditions.fileExtensions.map { ".\($0)" }.joined(separator: "/"))
        }
        if !action.conditions.pathPrefixes.isEmpty { parts.append(L10n.tr("限定目录")) }
        return parts.joined(separator: "、")
    }

    private func moveButton(_ systemName: String, offset: Int) -> some View {
        Button {
            store.move(action, by: offset)
        } label: {
            Image(systemName: systemName)
                .frame(width: 23, height: 23)
                .contentShape(Rectangle())
        }
        .disabled(!allowsReordering || !store.canMove(action, by: offset))
        .help(offset < 0 ? L10n.tr("上移") : L10n.tr("下移"))
        .accessibilityLabel(offset < 0 ? L10n.tr("上移“%@”", String(describing: action.localizedTitle)) : L10n.tr("下移“%@”", String(describing: action.localizedTitle)))
    }
}

private struct ActionEditor: View {
    @ObservedObject private var language = LanguageStore.shared
    @Environment(\.dismiss) private var dismiss
    let groups: [ActionGroup]
    let onSave: (ConfiguredAction) -> Void
    @State private var action: ConfiguredAction
    @State private var extensionText: String

    init(action: ConfiguredAction, groups: [ActionGroup], onSave: @escaping (ConfiguredAction) -> Void) {
        self.groups = groups
        self.onSave = onSave
        _action = State(initialValue: action)
        _extensionText = State(initialValue: action.conditions.fileExtensions.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.tr("菜单")) {
                    TextField(L10n.tr("菜单名称"), text: Binding(get: { action.localizedTitle }, set: { action.title = $0 }))
                    TextField(L10n.tr("SF Symbol 图标"), text: $action.symbolName)
                    Picker(L10n.tr("分组"), selection: $action.groupID) {
                        Text(L10n.tr("不分组")).tag(String?.none)
                        ForEach(groups) { group in
                            Text(group.localizedTitle).tag(Optional(group.id))
                        }
                    }
                    Toggle(L10n.tr("启用动作"), isOn: $action.isEnabled)
                    Toggle(L10n.tr("收藏到一级右键菜单"), isOn: $action.isFavorite)
                }

                typeSpecificSection

                Section(L10n.tr("显示条件")) {
                    HStack {
                        Toggle(L10n.tr("文件"), isOn: $action.conditions.allowsFiles)
                        Toggle(L10n.tr("文件夹"), isOn: $action.conditions.allowsFolders)
                        Toggle(L10n.tr("Finder 空白处"), isOn: $action.conditions.allowsContainer)
                    }
                    TextField(L10n.tr("文件扩展名，例如 md, swift, json；留空表示不限"), text: $extensionText)
                        .disabled(!action.conditions.allowsFiles)
                    Stepper(
                        L10n.tr("最少选择 %@ 项", String(describing: action.conditions.minimumSelectionCount)),
                        value: $action.conditions.minimumSelectionCount,
                        in: 1...99
                    )
                    .disabled(!hasItemContext)
                    Stepper(
                        maximumSelectionLabel,
                        value: Binding(
                            get: { action.conditions.maximumSelectionCount ?? 0 },
                            set: { action.conditions.maximumSelectionCount = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...99
                    )
                    .disabled(!hasItemContext)
                    Text(hasItemContext
                         ? L10n.tr("选择数量和扩展名只用于文件或文件夹；Finder 空白处和工具栏未选择项目时不受这些条件限制。")
                         : L10n.tr("当前动作只显示在 Finder 空白处和工具栏未选择项目时；选择数量与扩展名不适用。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("作用目录")) {
                    if action.conditions.pathPrefixes.isEmpty {
                        Text(L10n.tr("所有目录"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(action.conditions.pathPrefixes, id: \.self) { path in
                            HStack {
                                Text(path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button(L10n.tr("移除")) {
                                    action.conditions.pathPrefixes.removeAll { $0 == path }
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    Button(L10n.tr("添加作用目录…"), systemImage: "folder.badge.plus", action: chooseScopeDirectory)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text(validationMessage ?? L10n.tr("所选路径在执行时会再次检查。"))
                    .font(.caption)
                    .foregroundStyle(validationMessage == nil ? Color.secondary : Color.red)
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
            .padding(16)
        }
        .frame(width: 650, height: editorHeight)
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch action.kind {
        case .builtIn:
            Section(L10n.tr("基础动作")) {
                LabeledContent(L10n.tr("操作"), value: builtInTitle)
            }
        case .application, .terminal:
            Section(action.kind.title) {
                LabeledContent(L10n.tr("位置"), value: action.targetPath ?? L10n.tr("未选择"))
                Button(action.installedApplicationURL() == nil ? L10n.tr("重新选择应用…") : L10n.tr("更换应用…")) {
                    chooseTargetApplication()
                }
            }
        case .directory:
            Section(L10n.tr("常用目录")) {
                LabeledContent(L10n.tr("位置"), value: action.targetPath ?? L10n.tr("未选择"))
                Button(targetDirectoryExists ? L10n.tr("更换目录…") : L10n.tr("重新选择目录…")) {
                    chooseTargetDirectory()
                }
            }
        case .template:
            Section(L10n.tr("文件模板")) {
                TextField(L10n.tr("扩展名"), text: Binding(
                    get: { action.templateExtension ?? "" },
                    set: { action.templateExtension = $0 }
                ))
                Text(L10n.tr("模板内容"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { action.templateContent ?? "" },
                    set: { action.templateContent = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
            }
        case .shell, .appleScript:
            Section(action.kind.title) {
                Text(action.kind == .shell
                     ? L10n.tr("所选路径会作为 $1、$2… 传入；$RCA_DIRECTORY 是当前目录。")
                     : L10n.tr("所选路径会传给 on run argv。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { action.script ?? "" },
                    set: { action.script = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
            }
        }
    }

    private var builtInTitle: String {
        switch action.builtInOperation {
        case .copyPath: L10n.tr("复制路径")
        case .copyName: L10n.tr("复制文件名")
        case .cut: L10n.tr("剪切")
        case .paste: L10n.tr("粘贴")
        case nil: L10n.tr("未知")
        }
    }

    private var maximumSelectionLabel: String {
        action.conditions.maximumSelectionCount.map { L10n.tr("最多选择 %@ 项", String(describing: $0)) } ?? L10n.tr("选择数量不设上限")
    }

    private var hasItemContext: Bool {
        action.conditions.allowsFiles || action.conditions.allowsFolders
    }

    private var targetDirectoryExists: Bool {
        guard let targetPath = action.targetPath else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private var validationMessage: String? {
        if action.localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L10n.tr("菜单名称不能为空。") }
        if !action.conditions.allowsFiles && !action.conditions.allowsFolders && !action.conditions.allowsContainer {
            return L10n.tr("至少选择一种显示位置。")
        }
        if action.kind == .template {
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUnsafePathComponent(title) { return L10n.tr("模板名称不能是 . 或 ..，也不能包含路径分隔符。") }
            let fileExtension = action.normalizedTemplateExtension
            if fileExtension.isEmpty { return L10n.tr("模板扩展名不能为空。") }
            if isUnsafePathComponent(fileExtension) { return L10n.tr("模板扩展名不能是 . 或 ..，也不能包含路径分隔符。") }
        }
        if (action.kind == .shell || action.kind == .appleScript)
            && (action.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.tr("脚本内容不能为空。")
        }
        return nil
    }

    private var editorHeight: CGFloat {
        action.kind == .shell || action.kind == .appleScript || action.kind == .template ? 760 : 650
    }

    private func save() {
        action.title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        action.symbolName = action.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.symbolName.isEmpty { action.symbolName = action.kind.symbolName }
        action.conditions.fileExtensions = ActionConditions.normalizeExtensions(
            extensionText.components(separatedBy: CharacterSet(charactersIn: ",，;； \n"))
        )
        if let maximum = action.conditions.maximumSelectionCount,
           maximum < action.conditions.minimumSelectionCount {
            action.conditions.maximumSelectionCount = action.conditions.minimumSelectionCount
        }
        onSave(action)
        dismiss()
    }

    private func chooseScopeDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择动作生效的目录")
        panel.prompt = L10n.tr("添加")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path,
              !action.conditions.pathPrefixes.contains(path) else { return }
        action.conditions.pathPrefixes.append(path)
    }

    private func chooseTargetApplication() {
        let oldTarget = action.targetPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let shouldRefreshTitle = oldTarget == nil
            || oldTarget.map { action.title == automaticApplicationTitle(for: $0) } == true
        let panel = NSOpenPanel()
        panel.title = action.kind == .terminal ? L10n.tr("选择终端应用") : L10n.tr("选择打开文件的应用")
        panel.prompt = L10n.tr("选择")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action.targetPath = url.path
        let bundle = Bundle(url: url)
        action.bundleIdentifier = bundle?.bundleIdentifier
        if shouldRefreshTitle {
            action.title = automaticApplicationTitle(for: url)
        }
    }

    private func chooseTargetDirectory() {
        let oldTarget = action.targetPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let shouldRefreshTitle = oldTarget == nil
            || oldTarget.map { action.title == "打开 \($0.lastPathComponent)" } == true
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择常用目录")
        panel.prompt = L10n.tr("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action.targetPath = url.path
        if shouldRefreshTitle {
            action.title = "打开 \(url.lastPathComponent)"
        }
    }

    private func automaticApplicationTitle(for url: URL) -> String {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return action.kind == .terminal ? "在 \(name) 打开" : "使用 \(name) 打开"
    }

    private func isUnsafePathComponent(_ value: String) -> Bool {
        value == "."
            || value == ".."
            || value.contains("/")
            || value.contains("\\")
            || value.contains(":")
            || value.unicodeScalars.contains("\0")
    }
}

private struct GroupEditorContext: Identifiable {
    let id = UUID()
    var group: ActionGroup
    var isNew: Bool
}

private struct GroupEditor: View {
    @ObservedObject private var language = LanguageStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var group: ActionGroup
    let isNew: Bool
    let onSave: (ActionGroup) -> Void

    init(group: ActionGroup, isNew: Bool, onSave: @escaping (ActionGroup) -> Void) {
        _group = State(initialValue: group)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(L10n.tr("分组名称"), text: Binding(get: { group.localizedTitle }, set: { group.title = $0 }))
                TextField(L10n.tr("SF Symbol 图标"), text: $group.symbolName)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? L10n.tr("创建") : L10n.tr("保存")) {
                    group.title = group.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    group.symbolName = group.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if group.symbolName.isEmpty { group.symbolName = "folder" }
                    onSave(group)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(group.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 210)
    }
}
