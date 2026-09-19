import SwiftUI
import FinderSync

struct SettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    var body: some View {
        Form {
            Section(L10n.tr("界面语言")) {
                Picker(L10n.tr("语言"), selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(choice.nativeName).tag(choice)
                    }
                }
                Text(L10n.tr("界面和 Finder 菜单会即时切换。Dock 名称在重新打开应用后刷新。"))
                    .foregroundStyle(.secondary)
            }
            Section(L10n.tr("启用 Finder 扩展")) {
                Text(L10n.tr("点击下方按钮打开系统扩展管理界面，然后启用“右键助手扩展”。如果没有自动定位，可在“系统设置 → 通用 → 登录项与扩展”中查找 Finder 扩展。"))
                    .foregroundStyle(.secondary)
                Button(L10n.tr("打开登录项与扩展设置")) {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 360)
    }
}
