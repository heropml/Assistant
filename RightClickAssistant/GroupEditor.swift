import SwiftUI

struct GroupEditorContext: Identifiable {
    let id = UUID()
    var group: ActionGroup
    var isNew: Bool
}

struct GroupEditor: View {
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
