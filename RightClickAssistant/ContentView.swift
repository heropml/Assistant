import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ActionStore
    @Environment(\.openSettings) private var openSettings
    @State private var editingAction: ConfiguredAction?
    @State private var groupEditor: GroupEditorContext?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            actionList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.gradient)
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: .blue.opacity(0.18), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("右键助手")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("一套动作栈，按当前文件和目录自动显示")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Label("\(store.enabledCount) 项启用 · \(store.favoriteCount) 项直达", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Button("扩展设置…") { openSettings() }
                    .buttonStyle(.link)
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
                TextField("搜索动作、类型或分组", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(width: 260, height: 30)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            Toggle("收藏显示在一级菜单", isOn: Binding(
                get: { store.configuration.showsFavoritesAtTopLevel },
                set: { store.setShowsFavoritesAtTopLevel($0) }
            ))
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                groupEditor = GroupEditorContext(group: ActionGroup(title: "新分组"), isNew: true)
            } label: {
                Label("新建分组", systemImage: "folder.badge.plus")
            }

            addActionMenu
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var addActionMenu: some View {
        Menu {
            Menu("基础动作") {
                Button("复制路径") { editBuiltIn(.copyPath) }
                Button("复制文件名") { editBuiltIn(.copyName) }
                Button("剪切") { editBuiltIn(.cut) }
                Button("粘贴已剪切项目") { editBuiltIn(.paste) }
            }
            Divider()
            Button("应用…", systemImage: "app") { chooseApplication(kind: .application) }
            Button("终端…", systemImage: "apple.terminal") { chooseApplication(kind: .terminal) }
            Button("常用目录…", systemImage: "folder") { chooseDirectory() }
            Divider()
            Button("文件模板", systemImage: "doc.badge.plus") { editingAction = store.draft(for: .template) }
            Button("Shell 脚本", systemImage: "chevron.left.forwardslash.chevron.right") { editingAction = store.draft(for: .shell) }
            Button("AppleScript", systemImage: "applescript") { editingAction = store.draft(for: .appleScript) }
        } label: {
            Label("添加动作", systemImage: "plus")
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
                        Text("动作栈")
                            .font(.headline)
                        Text("拖动任意动作可跨类型排序")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(filteredActions.count) 项")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    if filteredActions.isEmpty {
                        ContentUnavailableView(
                            "没有匹配的动作",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("更换搜索词，或从右上角添加新动作。")
                        )
                        .frame(minHeight: 220)
                    } else {
                        ForEach(filteredActions) { action in
                            ActionRow(
                                action: action,
                                groupTitle: groupTitle(for: action),
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
                Text("菜单分组")
                    .font(.headline)
                Spacer()
                Text("未分组动作直接显示在“右键助手”子菜单中")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.groups) { group in
                        Menu {
                            Button("编辑") {
                                groupEditor = GroupEditorContext(group: group, isNew: false)
                            }
                            Divider()
                            Button("删除分组", role: .destructive) {
                                store.removeGroup(group)
                            }
                        } label: {
                            Label(group.title, systemImage: group.symbolName)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.blue.opacity(0.08), in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text("修改会即时写入 Finder 配置；脚本、模板与文件移动由右键助手主程序执行。")
            Spacer()
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
            action.title.lowercased().contains(query)
                || action.kind.title.lowercased().contains(query)
                || groupTitle(for: action).lowercased().contains(query)
        }
    }

    private func groupTitle(for action: ConfiguredAction) -> String {
        guard let groupID = action.groupID else { return "未分组" }
        return store.groups.first(where: { $0.id == groupID })?.title ?? "未分组"
    }

    private func editBuiltIn(_ operation: BuiltInOperation) {
        let values: (String, String, ActionConditions)
        switch operation {
        case .copyPath:
            values = ("复制路径", "point.topleft.down.to.point.bottomright.curvepath", ActionConditions())
        case .copyName:
            values = ("复制文件名", "doc.on.doc", ActionConditions())
        case .cut:
            values = ("剪切", "scissors", ActionConditions(allowsContainer: false))
        case .paste:
            values = (
                "粘贴已剪切项目",
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
        panel.title = kind == .terminal ? "选择终端应用" : "选择打开文件的应用"
        panel.prompt = "选择"
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
        panel.title = "选择常用目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editingAction = store.action(fromDirectoryURL: url)
    }
}

private struct ActionRow: View {
    @EnvironmentObject private var store: ActionStore
    let action: ConfiguredAction
    let groupTitle: String
    let onEdit: () -> Void
    let onDropAction: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .help("拖动排序")

            actionIcon
                .frame(width: 38, height: 38)
                .background(kindColor.opacity(action.isEnabled ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(action.title)
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
                            .help("一级菜单直达")
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
            .help(action.isFavorite ? "取消一级菜单直达" : "添加到一级菜单")

            HStack(spacing: 2) {
                moveButton("chevron.up", offset: -1)
                moveButton("chevron.down", offset: 1)
            }
            .buttonStyle(.borderless)

            Menu {
                Button("编辑", systemImage: "slider.horizontal.3", action: onEdit)
                Divider()
                Button("删除", systemImage: "trash", role: .destructive) { store.remove(action) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Toggle("", isOn: Binding(
                get: { action.isEnabled },
                set: { store.setEnabled($0, for: action) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
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
            guard let identifier = identifiers.first else { return false }
            onDropAction(identifier)
            return true
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
        if action.conditions.allowsFiles { parts.append("文件") }
        if action.conditions.allowsFolders { parts.append("文件夹") }
        if action.conditions.allowsContainer { parts.append("空白处") }
        if !action.conditions.fileExtensions.isEmpty {
            parts.append(action.conditions.fileExtensions.map { ".\($0)" }.joined(separator: "/"))
        }
        if !action.conditions.pathPrefixes.isEmpty { parts.append("限定目录") }
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
        .disabled(!store.canMove(action, by: offset))
        .help(offset < 0 ? "上移" : "下移")
    }
}

private struct ActionEditor: View {
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
                Section("菜单") {
                    TextField("菜单名称", text: $action.title)
                    TextField("SF Symbol 图标", text: $action.symbolName)
                    Picker("分组", selection: $action.groupID) {
                        Text("不分组").tag(String?.none)
                        ForEach(groups) { group in
                            Text(group.title).tag(Optional(group.id))
                        }
                    }
                    Toggle("启用动作", isOn: $action.isEnabled)
                    Toggle("收藏到一级右键菜单", isOn: $action.isFavorite)
                }

                typeSpecificSection

                Section("显示条件") {
                    HStack {
                        Toggle("文件", isOn: $action.conditions.allowsFiles)
                        Toggle("文件夹", isOn: $action.conditions.allowsFolders)
                        Toggle("Finder 空白处", isOn: $action.conditions.allowsContainer)
                    }
                    TextField("文件扩展名，例如 md, swift, json；留空表示不限", text: $extensionText)
                        .disabled(!action.conditions.allowsFiles)
                    Stepper(
                        "最少选择 \(action.conditions.minimumSelectionCount) 项",
                        value: $action.conditions.minimumSelectionCount,
                        in: 1...99
                    )
                    Stepper(
                        maximumSelectionLabel,
                        value: Binding(
                            get: { action.conditions.maximumSelectionCount ?? 0 },
                            set: { action.conditions.maximumSelectionCount = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...99
                    )
                }

                Section("作用目录") {
                    if action.conditions.pathPrefixes.isEmpty {
                        Text("所有目录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(action.conditions.pathPrefixes, id: \.self) { path in
                            HStack {
                                Text(path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("移除") {
                                    action.conditions.pathPrefixes.removeAll { $0 == path }
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    Button("添加作用目录…", systemImage: "folder.badge.plus", action: chooseScopeDirectory)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text(validationMessage ?? "所选路径在执行时会再次检查。")
                    .font(.caption)
                    .foregroundStyle(validationMessage == nil ? Color.secondary : Color.red)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
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
            Section("基础动作") {
                LabeledContent("操作", value: builtInTitle)
            }
        case .application, .terminal:
            Section(action.kind.title) {
                LabeledContent("位置", value: action.targetPath ?? "未选择")
            }
        case .directory:
            Section("常用目录") {
                LabeledContent("位置", value: action.targetPath ?? "未选择")
            }
        case .template:
            Section("文件模板") {
                TextField("扩展名", text: Binding(
                    get: { action.templateExtension ?? "" },
                    set: { action.templateExtension = $0 }
                ))
                Text("模板内容")
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
                     ? "所选路径会作为 $1、$2… 传入；$RCA_DIRECTORY 是当前目录。"
                     : "所选路径会传给 on run argv。")
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
        case .copyPath: "复制路径"
        case .copyName: "复制文件名"
        case .cut: "剪切"
        case .paste: "粘贴"
        case nil: "未知"
        }
    }

    private var maximumSelectionLabel: String {
        action.conditions.maximumSelectionCount.map { "最多选择 \($0) 项" } ?? "选择数量不设上限"
    }

    private var validationMessage: String? {
        if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "菜单名称不能为空。" }
        if !action.conditions.allowsFiles && !action.conditions.allowsFolders && !action.conditions.allowsContainer {
            return "至少选择一种显示位置。"
        }
        if action.kind == .template && action.normalizedTemplateExtension.isEmpty { return "模板扩展名不能为空。" }
        if (action.kind == .shell || action.kind == .appleScript)
            && (action.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "脚本内容不能为空。"
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
        panel.title = "选择动作生效的目录"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path,
              !action.conditions.pathPrefixes.contains(path) else { return }
        action.conditions.pathPrefixes.append(path)
    }
}

private struct GroupEditorContext: Identifiable {
    let id = UUID()
    var group: ActionGroup
    var isNew: Bool
}

private struct GroupEditor: View {
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
                TextField("分组名称", text: $group.title)
                TextField("SF Symbol 图标", text: $group.symbolName)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "创建" : "保存") {
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
