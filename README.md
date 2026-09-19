# 右键助手

一个可配置的 macOS Finder 右键动作平台。主应用管理统一动作栈和显示条件，Finder Sync 扩展只负责采集上下文和生成菜单；脚本、模板及文件移动由宿主应用执行。

## 当前功能

- 统一动作类型：基础动作、应用、终端、常用目录、文件模板、Shell、AppleScript
- 上下文条件：文件、文件夹、Finder 空白处、扩展名、选择数量和作用目录
- 菜单组织：统一排序、拖拽调整、分组、自定义 SF Symbol、一级收藏直达
- 文件操作：复制路径、复制文件名、剪切和粘贴
- 模板新建：自定义扩展名与初始内容
- 从“应用程序”中添加任意应用或终端，不依赖内置应用列表
- Shell 脚本通过 zsh 执行，所选路径作为位置参数传入，当前目录通过 `$RCA_DIRECTORY` 提供
- AppleScript 通过 `osascript` 执行，所选路径传给 `on run argv`
- V1 配置自动迁移到版本化 V2 配置
- 配置备份：窗口右上角「配置备份」导出 JSON；导入前校验版本和内容，并确认动作、分组及脚本数量后替换当前配置
- 执行反馈：菜单栏显示运行中的动作数，主窗口可展开本次运行记录，保留最近 20 条完成结果及失败详情
- 并发保护：后台等待全部已接收动作完成后退出；新建模板不覆盖同名文件；粘贴期间的新剪切不会被旧任务清空

执行记录仅保留在本次进程中。通过 Finder 临时启动的后台进程完成后自动退出；执行期间从菜单栏打开主窗口可保留应用和记录。

## 核心测试（无需打包）

```sh
./Scripts/test-core.sh
```

覆盖配置导入导出、菜单缓存失效、条件查询复用、任务退出顺序、剪切批次、64 路并发新建及原有脚本执行测试，并对主应用和 Finder 扩展做 Swift 6 严格并发类型检查。

仅安装 Command Line Tools，或完整 Xcode 暂不可用时，可以运行：

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools ./Scripts/test-core.sh
```

若预览版 SDK 的 SwiftUI 宏插件缺失，可通过 `SDKROOT` 指定本机已安装的稳定 SDK，例如在上述命令前再设置 `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`。

## 直接使用（无需开发者账号）

仓库中的个人版使用本机 ad-hoc 签名，不需要 Apple ID、开发者证书或 provisioning profile。

1. 运行 `./Scripts/build-local.sh`，完成后使用生成的 `dist/RightClickAssistant.app`。
2. 建议把应用拖入“应用程序”文件夹，然后打开一次。
3. 在应用中点击“扩展设置… → 打开登录项与扩展设置”，启用“右键助手扩展”。
4. 如果 Finder 菜单没有立即出现，请重新打开 Finder 窗口。

> 本地签名版适合这台 Mac 自用。发送给其他人时没有 Developer ID 与 Apple 公证，Gatekeeper 可能拦截；正式分发时应恢复开发团队签名、沙盒/App Group，并进行公证。

## 验证

```bash
./Scripts/verify-local.sh
```

## GitHub 更新（v1.0.0 起）

窗口右下角显示应用版本，点击「检查更新」读取 GitHub 的版本清单。新版本会展示更新说明，用户确认下载后显示进度；下载完成后校验文件大小和 SHA-256，再打开 ARM DMG。退出旧应用后，将新版拖入「应用程序」替换，现有动作配置保留。检查和下载均可取消，不会在后台自动安装。

更新流程与 SerialTool 的 macOS 版本一致，清单使用 `version`、`url_mac`（单个 HTTPS 地址或地址数组）、`sha256_mac`、`size_mac`、`notes`，并增加 `arch_mac: "arm64"`。GitHub 下载地址优先。

当前更新清单地址为 `https://raw.githubusercontent.com/heropml/Assistant/main/latest.json`。清单及安装包需要允许公开访问。若更换发布仓库，须同步修改主应用 `Info.plist` 中的 `RCAUpdateManifestURL`、`RCAReleasesURL`。客户端不内置 GitHub Token。

发版流程：

1. 更新 Xcode 项目的 `MARKETING_VERSION`（正式版本，如 `1.0.1`）及 `CURRENT_PROJECT_VERSION`，构建 ARM 应用。
2. 执行 `./Scripts/package-update.sh "本次更新说明"`，生成版本化 ARM DMG 和包含实际校验值的 `dist/latest.json`。独立发布仓库可用 `RCA_RELEASE_REPOSITORY=owner/repo` 指定。
3. 将 DMG 上传至对应公开仓库的 `v<版本号>` Release，再将生成的清单发布到客户端配置的 `latest.json` 地址。须先上传安装包再更新清单。

打包脚本只在本地生成文件，不会创建 Release、推送代码或改变仓库可见性。`Scripts/test-core.sh` 包含版本比较、更新清单解析、校验失败、404 和取消请求的回归测试。

## 名称与中英文切换

主窗口右上角的地球图标可切换「简体中文 / English」，设置页也提供相同选项。主界面、执行反馈、更新窗口及下一次打开的 Finder 菜单会即时使用所选语言。默认动作和默认分组按显示语言翻译，自定义名称、脚本、模板内容及已有配置不会因语言切换而改写。

应用名称为「右键助手 / Right-Click Assistant」。本地化的应用名称和 macOS 系统菜单会在退出并重新打开应用后刷新。应用及扩展都包含中英文 `InfoPlist.strings`；打包时须保留两组 `.lproj` 资源。
