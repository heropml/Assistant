import SwiftUI
import UniformTypeIdentifiers

struct ActionEditor: View {
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
                if action.builtInOperation == .copyPath {
                    Picker(L10n.tr("复制格式"), selection: $action.pathCopyFormat) {
                        ForEach(PathCopyFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    Text(action.pathCopyFormat.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                LabeledContent(L10n.tr("超时（秒）")) {
                    HStack(spacing: 6) {
                        TextField("", value: scriptTimeoutBinding, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Stepper("", value: scriptTimeoutBinding, in: ConfiguredAction.scriptTimeoutRange, step: 10)
                            .labelsHidden()
                    }
                }
                Text(L10n.tr(
                    "超过时间后会停止脚本及其子进程，范围 %@–%@ 秒。",
                    String(describing: ConfiguredAction.scriptTimeoutRange.lowerBound),
                    String(describing: ConfiguredAction.scriptTimeoutRange.upperBound)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var scriptTimeoutBinding: Binding<Int> {
        Binding(
            get: { action.effectiveScriptTimeout },
            set: { newValue in
                action.scriptTimeout = newValue
                let clamped = action.effectiveScriptTimeout
                // Keep the default out of saved configurations.
                action.scriptTimeout = clamped == ConfiguredAction.defaultScriptTimeout ? nil : clamped
            }
        )
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
        let preferred: CGFloat = switch action.kind {
        case .shell, .appleScript: 820
        case .template: 760
        default: 650
        }
        // Leave room for the sheet's title bar so Save stays reachable on small
        // or scaled displays; the form scrolls when it is shorter than preferred.
        let available = (NSScreen.main?.visibleFrame.height ?? preferred) - 60
        return max(480, min(preferred, available))
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
