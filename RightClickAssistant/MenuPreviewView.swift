import SwiftUI

struct MenuPreviewView: View {
    let configuration: AssistantConfiguration

    @ObservedObject private var language = LanguageStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SampleMode = .selection
    @State private var sampleURLs: [URL] = []
    @State private var sampleError: String?
    @State private var isDropTargeted = false

    private enum SampleMode: String, CaseIterable, Identifiable {
        case selection
        case container

        var id: String { rawValue }
        var title: String {
            switch self {
            case .selection: L10n.tr("选中文件或文件夹")
            case .container: L10n.tr("文件夹空白处")
            }
        }
    }

    private var snapshot: MenuPreviewSnapshot {
        MenuPreviewSnapshot(configuration: configuration, urls: sampleURLs, isContainer: mode == .container)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label(L10n.tr("菜单预览"), systemImage: "menubar.rectangle")
                    .font(.title2.bold())
                Text(L10n.tr("选择样例，查看会显示的动作及隐藏原因。预览不会执行动作。"))
                    .foregroundStyle(.secondary)
            }
            samplePicker
            if let sampleError {
                Label(sampleError, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if sampleURLs.isEmpty {
                ContentUnavailableView {
                    Label(L10n.tr("尚未选择样例"), systemImage: "doc.viewfinder")
                } description: {
                    Text(L10n.tr("选择或拖入文件、文件夹，即可预览当前配置。"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let preview = snapshot
                HStack(alignment: .top, spacing: 20) {
                    menuColumn(preview)
                    hiddenColumn(preview)
                }
                .frame(maxHeight: .infinity)
            }
            HStack {
                Text(L10n.tr("一级菜单最多显示 6 个收藏，其余动作放在“右键助手”子菜单。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 820, height: 660)
        .onChange(of: mode) { _, newMode in
            if newMode == .container {
                sampleURLs = Array(sampleURLs.filter(Self.isDirectory).prefix(1))
            }
            sampleError = nil
        }
    }

    private var samplePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.tr("右键位置"), selection: $mode) {
                ForEach(SampleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 12) {
                Image(systemName: mode == .container ? "folder" : "doc.on.doc")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sampleURLs.isEmpty ? L10n.tr("将样例拖到这里") : L10n.tr("已选择 %@ 个项目", String(sampleURLs.count)))
                        .font(.callout.weight(.medium))
                    if !sampleURLs.isEmpty {
                        Text(sampleURLs.map(\.lastPathComponent).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(sampleURLs.map(\.path).joined(separator: "\n"))
                    } else {
                        Text(mode == .container ? L10n.tr("选择一个文件夹，模拟在其中的空白处右键。") : L10n.tr("可同时选择多个文件和文件夹。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(L10n.tr("选择样例…")) { chooseSamples() }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2)))
            .dropDestination(for: URL.self) { urls, _ in
                acceptSamples(urls)
            } isTargeted: { isDropTargeted = $0 }
        }
    }

    private func menuColumn(_ preview: MenuPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("会显示 · %@", String(preview.visibleCount)))
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if preview.visibleCount == 0 {
                        Text(L10n.tr("当前样例没有可显示的动作。"))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    ForEach(preview.favorites) { action in
                        actionRow(action)
                    }
                    if !preview.sections.isEmpty {
                        if !preview.favorites.isEmpty { Divider().padding(.vertical, 4) }
                        HStack {
                            Label(L10n.tr("右键助手"), systemImage: "cursorarrow.click.2")
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(preview.sections.enumerated()), id: \.element.id) { index, section in
                                if index > 0 { Divider().padding(.vertical, 4) }
                                if let group = section.group {
                                    Label(group.localizedTitle, systemImage: group.symbolName)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                }
                                ForEach(section.actions) { action in
                                    actionRow(action)
                                }
                            }
                        }
                        .padding(.leading, 18)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionRow(_ action: ConfiguredAction) -> some View {
        Label(action.localizedTitle, systemImage: action.symbolName)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hiddenColumn(_ preview: MenuPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("已隐藏 · %@", String(preview.hiddenActions.count)))
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if preview.hiddenActions.isEmpty {
                        Label(L10n.tr("所有动作均符合当前样例。"), systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(preview.hiddenActions) { hidden in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(hidden.action.localizedTitle, systemImage: hidden.action.symbolName)
                                .font(.callout.weight(.medium))
                            ForEach(Array(hidden.reasons.enumerated()), id: \.offset) { _, reason in
                                Text(reason.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseSamples() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择样例")
        panel.prompt = L10n.tr("预览")
        panel.canChooseFiles = mode == .selection
        panel.canCreateDirectories = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = mode == .selection
        guard panel.runModal() == .OK else { return }
        _ = acceptSamples(panel.urls)
    }

    private func acceptSamples(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }) else {
            sampleError = L10n.tr("请选择本机上存在的文件或文件夹。")
            return false
        }
        if mode == .container, urls.count != 1 || !Self.isDirectory(urls[0]) {
            sampleError = L10n.tr("文件夹空白处预览需要选择一个文件夹。")
            return false
        }
        sampleURLs = urls
        sampleError = nil
        return true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
