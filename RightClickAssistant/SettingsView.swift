import SwiftUI
import FinderSync

struct SettingsView: View {
    var body: some View {
        Form {
            Section("启用 Finder 扩展") {
                Text("点击下方按钮打开系统扩展管理界面，然后启用“右键助手扩展”。如果没有自动定位，可在“系统设置 → 通用 → 登录项与扩展”中查找 Finder 扩展。")
                    .foregroundStyle(.secondary)
                Button("打开登录项与扩展设置") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 220)
    }
}
