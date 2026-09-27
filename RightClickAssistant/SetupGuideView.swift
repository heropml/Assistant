import AppKit
import FinderSync
import SwiftUI

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = LanguageStore.shared
    @State private var showsOpenError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("开始使用右键助手"))
                    .font(.title2.bold())
                Text(L10n.tr("启用 Finder 扩展后，在文件、文件夹或空白处右键使用动作。"))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            FinderExtensionStatusView()
                            Text(L10n.tr("在系统设置中启用“右键助手扩展”。返回应用后会重新检查状态。"))
                                .foregroundStyle(.secondary)
                            Button(L10n.tr("打开登录项与扩展设置")) {
                                FIFinderSyncController.showExtensionManagementInterface()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    } label: {
                        Label(L10n.tr("1. 启用 Finder 扩展"), systemImage: "puzzlepiece.extension")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.tr("选择一个本地文件夹，在 Finder 中打开后右键空白处，查找“新建文本文件”或“右键助手”。"))
                            Button(L10n.tr("选择文件夹并在 Finder 中打开"), action: openTestFolder)
                            Text(L10n.tr("此按钮只打开文件夹，不会创建或修改文件。也可选中文件或文件夹，检查“复制路径”等动作。"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    } label: {
                        Label(L10n.tr("2. 在 Finder 中检查菜单"), systemImage: "cursorarrow.click.2")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("扩展已启用只代表系统开关已打开，菜单是否出现仍需在 Finder 中确认。"))
                            Text(L10n.tr("确认动作已启用；菜单位置、文件类型和选择数量条件也会影响显示。可通过主界面的“菜单预览”查看原因。"))
                            Text(L10n.tr("若菜单仍未出现，尝试重新打开 Finder 窗口，并确认系统设置中的扩展已启用。"))
                            Text(L10n.tr("iCloud、OneDrive、Dropbox 等云盘目录可能由其他扩展管理。请先在本地文件夹测试，再比较云盘目录。"))
                            Text(L10n.tr("不同 macOS 版本的设置位置可能不同，可在系统设置中搜索“扩展”或“Finder”。"))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    } label: {
                        Label(L10n.tr("菜单没有出现？"), systemImage: "questionmark.circle")
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.tr("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580, height: 620)
        .alert(L10n.tr("无法打开文件夹"), isPresented: $showsOpenError) {
            Button(L10n.tr("好"), role: .cancel) { }
        } message: {
            Text(L10n.tr("请确认文件夹仍然存在且可以访问，然后重新选择。"))
        }
    }

    private func openTestFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择用于检查菜单的文件夹")
        panel.prompt = L10n.tr("在 Finder 中打开")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        showsOpenError = !NSWorkspace.shared.open(url)
    }
}

struct FinderExtensionStatusView: View {
    @ObservedObject private var language = LanguageStore.shared
    @EnvironmentObject private var store: ActionStore
    @State private var isEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var confirmsRestart = false
    @State private var restartError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Label(
                L10n.tr(isEnabled ? "Finder 扩展已启用" : "尚未检测到扩展启用"),
                systemImage: isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            .foregroundStyle(isEnabled ? Color.green : Color.orange)
                Spacer()
                Button(L10n.tr("重启应用"), systemImage: "arrow.clockwise.circle") {
                    confirmsRestart = true
                }
                .disabled(store.runningExecutionCount > 0)
                Button(L10n.tr("刷新状态"), systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.titleAndIcon)
            }
          Text(L10n.tr(store.runningExecutionCount > 0
              ? "有动作正在执行，请等待完成后再重启。"
              : "若系统开关已开启但状态未更新，可重启应用重新检测。重启不会更改系统扩展开关。"))
              .font(.caption)
              .foregroundStyle(.secondary)
        }
        .confirmationDialog(L10n.tr("重启右键助手？"), isPresented: $confirmsRestart) {
            Button(L10n.tr("重启应用")) {
                do {
                    try ApplicationRestart.restart(runningActionCount: store.runningExecutionCount)
                } catch {
                    restartError = error.localizedDescription
                }
            }
            Button(L10n.tr("取消"), role: .cancel) { }
        } message: {
            Text(L10n.tr("已保存的配置会保留，未保存的编辑将丢失。应用将从当前位置重新打开。"))
        }
        .alert(L10n.tr("无法重启应用"), isPresented: Binding(
            get: { restartError != nil }, set: { if !$0 { restartError = nil } }
        )) {
            Button(L10n.tr("好"), role: .cancel) { restartError = nil }
        } message: {
            Text(restartError ?? "")
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }
}
