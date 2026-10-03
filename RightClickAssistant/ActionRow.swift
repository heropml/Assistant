import SwiftUI

struct ActionRow: View {
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
