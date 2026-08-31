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

## 直接使用（无需开发者账号）

仓库中的个人版使用本机 ad-hoc 签名，不需要 Apple ID、开发者证书或 provisioning profile。

1. 运行 `./Scripts/build-local.sh`，或直接使用已经生成的 `dist/RightClickAssistant.app`。
2. 建议把应用拖入“应用程序”文件夹，然后打开一次。
3. 在应用中点击“扩展设置… → 打开登录项与扩展设置”，启用“右键助手扩展”。
4. 如果 Finder 菜单没有立即出现，请重新打开 Finder 窗口。

> 本地签名版适合这台 Mac 自用。发送给其他人时没有 Developer ID 与 Apple 公证，Gatekeeper 可能拦截；正式分发时应恢复开发团队签名、沙盒/App Group，并进行公证。

## 验证

```bash
./Scripts/verify-local.sh
```
