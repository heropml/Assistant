# 右键助手

一个轻量的 macOS Finder 右键菜单配置工具。主应用用于启用、停用和排序动作，Finder Sync 扩展负责在 Finder 右键菜单中执行这些动作。

## 当前功能

- 复制路径
- 复制文件名
- 新建文本文件
- 在终端打开
- 从“应用程序”中添加任意应用作为打开方式，不依赖内置应用列表
- 自定义打开方式的菜单名称、启停和排序，并可随时移除
- 右键选中文件时打开所选项目；右键 Finder 空白处时打开当前文件夹
- 基础动作启停与排序

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
