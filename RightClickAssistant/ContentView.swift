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
    @State private var showsSetupGuide = false
    @State private var showsMenuPreview = false
    @AppStorage("hasSeenSetupGuideV1") private var hasSeenSetupGuide = false
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
        .sheet(isPresented: $showsSetupGuide, onDismiss: { hasSeenSetupGuide = true }) {
            SetupGuideView()
        }
        .sheet(isPresented: $showsMenuPreview) {
            MenuPreviewView(configuration: store.configuration)
        }
        .onAppear { presentSetupGuideIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            presentSetupGuideIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            presentSetupGuideIfNeeded()
        }
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
                    Button(L10n.tr("启用向导")) { showsSetupGuide = true }
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
            .frame(minWidth: 140, idealWidth: 220, maxWidth: 260, minHeight: 30, maxHeight: 30)
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

            Button {
                showsMenuPreview = true
            } label: {
                Label(L10n.tr("菜单预览"), systemImage: "eye")
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
            Menu {
                ForEach(TemplatePreset.allCases) { preset in
                    Button("\(preset.title) (.\(preset.fileExtension))") {
                        editingAction = preset.makeAction(groups: store.groups)
                    }
                }
                Divider()
                Button(L10n.tr("自定义文本模板…")) { editingAction = store.draft(for: .template) }
            } label: {
                Label(L10n.tr("文件模板"), systemImage: "doc.badge.plus")
            }
            Button(L10n.tr("Shell 脚本"), systemImage: "chevron.left.forwardslash.chevron.right") { editingAction = store.draft(for: .shell) }
            Button("AppleScript", systemImage: "applescript") { editingAction = store.draft(for: .appleScript) }
        } label: {
            Label(L10n.tr("添加动作"), systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func presentSetupGuideIfNeeded() {
        guard !hasSeenSetupGuide, !showsSetupGuide,
              NSApp.activationPolicy() == .regular,
              let window = NSApp.keyWindow,
              window.isVisible,
              AppLanguage.allCases.map(\.appName).contains(window.title),
              !showsUpdate, !showsMenuPreview, editingAction == nil, groupEditor == nil else { return }
        showsSetupGuide = true
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
