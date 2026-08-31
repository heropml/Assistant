import SwiftUI
import FinderSync

struct SettingsView: View {
    var body: some View {
        Form {
            Section("启用 Finder 扩展") {
                Text("请前往“系统设置 → 通用 → 登录项与扩展 → 文件提供程序与 Finder 扩展”，启用“右键助手扩展”。")
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
