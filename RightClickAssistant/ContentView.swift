import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ActionStore
    @Environment(\.openSettings) private var openSettings
    @State private var editingApplication: ApplicationAction?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actionList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingApplication) { application in
            ApplicationActionEditor(application: application) { title in
                store.updateMenuTitle(title, for: application)
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
                Text("配置 Finder 右键菜单中的基础动作和打开方式")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Label("\(store.enabledCount) 项已启用", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Button("扩展设置…") { openSettings() }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private var actionList: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                builtInSection
                applicationSection
            }
            .padding(28)
        }
    }

    private var builtInSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "基础动作", detail: "使用箭头调整显示顺序")
            ForEach(store.actions) { action in
                BuiltInActionRow(action: action)
            }
        }
    }

    private var applicationSection: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("打开方式")
                        .font(.headline)
                    Text("选中文件时打开文件；空白处打开当前文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: chooseApplication) {
                    Label("添加应用", systemImage: "plus")
                }
            }

            if store.applicationActions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("还没有添加应用")
                            .font(.body.weight(.medium))
                        Text("选择任意 macOS 应用，把它加入 Finder 右键菜单。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.separator.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            } else {
                ForEach(store.applicationActions) { application in
                    ApplicationActionRow(
                        application: application,
                        onEdit: { editingApplication = application }
                    )
                }
            }
        }
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text("修改会立即同步到 Finder；若菜单未更新，请重新打开 Finder 窗口。")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要添加到右键菜单的应用"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addApplication(at: url)
    }
}

private struct BuiltInActionRow: View {
    @EnvironmentObject private var store: ActionStore
    let action: QuickAction

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: action.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(store.isEnabled(action) ? .blue : .secondary)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(store.isEnabled(action) ? 0.11 : 0.04), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.body.weight(.medium))
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            moveButtons
            Toggle("", isOn: Binding(
                get: { store.isEnabled(action) },
                set: { store.setEnabled($0, for: action) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .actionRowStyle()
    }

    private var moveButtons: some View {
        HStack(spacing: 3) {
            moveButton(systemName: "chevron.up", offset: -1)
            moveButton(systemName: "chevron.down", offset: 1)
        }
        .buttonStyle(.borderless)
    }

    private func moveButton(systemName: String, offset: Int) -> some View {
        Button {
            store.move(action, by: offset)
        } label: {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .disabled(!store.canMove(action, by: offset))
        .help(offset < 0 ? "上移" : "下移")
    }
}

private struct ApplicationActionRow: View {
    @EnvironmentObject private var store: ActionStore
    let application: ApplicationAction
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            applicationIcon
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(application.isEnabled ? 0.11 : 0.04), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(application.menuTitle)
                    .font(.body.weight(.medium))
                HStack(spacing: 7) {
                    Text(application.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if applicationURL == nil {
                        Text("应用已移动或删除")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            HStack(spacing: 3) {
                moveButton(systemName: "chevron.up", offset: -1)
                moveButton(systemName: "chevron.down", offset: 1)
            }
            .buttonStyle(.borderless)

            Menu {
                Button("修改菜单名称", systemImage: "pencil", action: onEdit)
                Divider()
                Button("移除", systemImage: "trash", role: .destructive) {
                    store.removeApplication(application)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Toggle("", isOn: Binding(
                get: { application.isEnabled },
                set: { store.setEnabled($0, for: application) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .actionRowStyle()
    }

    @ViewBuilder
    private var applicationIcon: some View {
        if let applicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                .resizable()
                .scaledToFit()
                .padding(6)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var applicationURL: URL? {
        application.installedApplicationURL()
    }

    private func moveButton(systemName: String, offset: Int) -> some View {
        Button {
            store.move(application, by: offset)
        } label: {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .disabled(!store.canMove(application, by: offset))
        .help(offset < 0 ? "上移" : "下移")
    }
}

private struct ApplicationActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let application: ApplicationAction
    let onSave: (String) -> Void
    @State private var menuTitle: String

    init(application: ApplicationAction, onSave: @escaping (String) -> Void) {
        self.application = application
        self.onSave = onSave
        _menuTitle = State(initialValue: application.menuTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("右键菜单名称") {
                    TextField("菜单名称", text: $menuTitle)
                }
                Section("应用") {
                    LabeledContent("名称", value: application.applicationName)
                    LabeledContent("位置", value: application.applicationPath)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(menuTitle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(menuTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 290)
    }
}

private extension View {
    func actionRowStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.55), lineWidth: 0.5)
            }
    }
}
