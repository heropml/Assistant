import SwiftUI

struct UpdateView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var updater: UpdateManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.tr("软件更新")).font(.title2.bold())
                Spacer()
                Text(L10n.tr("当前 v%@", String(describing: AppVersion.current))).foregroundStyle(.secondary)
            }
            content
            if let release = updater.release, !release.notes.isEmpty {
                ScrollView { Text(release.notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 150)
            }
            Divider()
            HStack {
                Link(L10n.tr("GitHub 发布页"), destination: UpdateClient.releasesURL)
                Spacer()
                if updater.isBusy {
                    Button(L10n.tr("取消")) { updater.cancel() }
                } else {
                    Button(L10n.tr("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
                    if case .available = updater.state {
                        Button(L10n.tr("下载并打开安装包")) { updater.download() }.keyboardShortcut(.defaultAction)
                    } else if case .ready(let file) = updater.state {
                        Button(L10n.tr("重新打开安装包")) { NSWorkspace.shared.open(file) }
                    } else {
                        Button(L10n.tr("重新检查")) { updater.check() }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear { updater.check() }
        .onDisappear { updater.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch updater.state {
        case .idle:
            Text(L10n.tr("检查 GitHub 上发布的新版本。"))
        case .checking:
            HStack { ProgressView().controlSize(.small); Text(L10n.tr("正在检查更新…")) }
        case .latest:
            Label(L10n.tr("当前已是最新版本"), systemImage: "checkmark.circle")
        case .available:
            Text(L10n.tr("发现新版本 v%@", String(describing: updater.release?.version.trimmingCharacters(in: CharacterSet(charactersIn: "v")) ?? "")))
                .font(.headline)
            Text(L10n.tr("下载完成后将校验安装包并打开 DMG，请退出右键助手后拖入“应用程序”替换安装。"))
                .foregroundStyle(.secondary)
        case .downloading(let fraction):
            ProgressView(value: fraction)
            Text(fraction < 1 ? L10n.tr("正在下载 %@%", String(describing: Int(fraction * 100))) : L10n.tr("下载完成，正在校验安装包…"))
                .foregroundStyle(.secondary)
        case .ready:
            Label(L10n.tr("安装包校验通过，已打开"), systemImage: "checkmark.shield")
            Text(L10n.tr("请退出右键助手，将安装包中的应用拖入“应用程序”并替换旧版，然后重新打开。现有动作配置会保留。"))
        case .failed(let message):
            Label(L10n.tr("更新未完成"), systemImage: "exclamationmark.triangle")
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
