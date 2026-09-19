# 右键助手 · Right-Click Assistant

[![macOS](https://img.shields.io/badge/macOS-14%2B-blue)](https://www.apple.com/macos/)
[![Architecture](https://img.shields.io/badge/Apple%20Silicon-arm64-black)](#安装与启用)
[![Swift](https://img.shields.io/badge/Swift-6-orange)](https://www.swift.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-green)](CHANGELOG.md)

一个可配置的 macOS Finder 右键助手，支持文件操作、应用启动、文件模板及脚本，并提供中英文界面。

A configurable Finder context-menu utility for macOS, with file actions, app launchers, templates, scripts, and Chinese/English interfaces.

[功能](#主要功能) · [安装](#安装与启用) · [开发](#开发与验证) · [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [问题反馈](https://github.com/heropml/Assistant/issues)

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 文件操作 | 复制路径、复制文件名、剪切、粘贴 |
| 打开方式 | 从“应用程序”选择应用或终端，打开所选项目或常用目录 |
| 文件模板 | 自定义扩展名和初始内容，新建时避免覆盖同名文件 |
| 脚本动作 | 执行 Shell 或 AppleScript，传入所选路径与当前目录 |
| 上下文条件 | 按文件、文件夹、空白处、扩展名、选择数量和作用目录显示 |
| 菜单管理 | 拖拽排序、分组、自定义 SF Symbol、一级收藏直达 |
| 配置备份 | 导入、导出 JSON，导入前校验并确认替换 |
| 执行反馈 | 显示运行任务及最近 20 条完成记录和失败详情 |
| 中英文切换 | 主界面、Finder 菜单及应用名称支持中文和英文 |
| GitHub 更新 | 检查版本、显示下载进度并校验安装包大小和 SHA-256 |

执行记录仅保留在本次进程中。由 Finder 临时启动的后台进程会在全部任务完成后退出；执行期间打开主窗口可保留应用和记录。

## 安装与启用

- 系统：macOS 14 或更新版本。
- 架构：Apple Silicon（arm64）；当前打包脚本不提供 Intel 安装包。
- 构建：需要支持 Swift 6 的 Xcode 及 macOS SDK。

### 从源码安装

```sh
git clone https://github.com/heropml/Assistant.git
cd Assistant
./Scripts/build-local.sh
```

1. 将生成的 `dist/RightClickAssistant.app` 拖入“应用程序”并打开一次。
2. 点击“扩展设置…”，打开系统的“登录项与扩展”设置，启用“右键助手扩展”。
3. 重新打开 Finder 窗口，在文件、文件夹或空白处使用右键菜单。

打包输出还包括 `dist/RightClickAssistant-macOS.zip`。发布后的安装包可在 [Releases](https://github.com/heropml/Assistant/releases) 获取；没有发布资产时请从源码构建。

当前构建使用本机 ad-hoc 签名，无需 Apple 开发者账号。该签名不等同于 Developer ID 签名或 Apple 公证，其他 Mac 上可能被 Gatekeeper 拦截。

## 使用说明

### 语言与名称

点击主窗口右上角的地球图标，或在设置中选择“简体中文 / English”。界面及下一次打开的 Finder 菜单即时切换；Dock 和 macOS 系统菜单中的应用名称在退出并重新打开后刷新。

中文名称为“右键助手”，英文名称为“Right-Click Assistant”。自定义动作名称、脚本、模板内容及已有配置不会因语言切换而改写。

### 配置与脚本

- 使用右上角“配置备份”导出 JSON；导入会在确认后替换当前配置。
- 旧配置会迁移到当前配置格式（V3）。
- Shell 由 `zsh` 执行，所选路径通过位置参数传入，当前目录通过 `$RCA_DIRECTORY` 提供。
- AppleScript 由 `osascript` 执行，所选路径传入 `on run argv`。

### 检查更新

点击窗口右下角的“检查更新”。发现新版本后可查看说明并下载 ARM DMG；校验通过后打开映像，退出旧应用并将新版拖入“应用程序”替换。现有配置保留，检查和下载均可取消。

更新清单位于 [`latest.json`](latest.json)，清单与对应 Release 安装包均须公开可读。客户端不内置 GitHub Token，也不会静默安装更新。

## 开发与验证

主应用使用 SwiftUI 管理动作与执行任务；Finder Sync 扩展采集上下文并生成菜单。

```text
RightClickAssistant/       主应用、设置、语言及更新界面
RightClickFinderExtension/ Finder Sync 扩展
Shared/                    配置、动作模型和本地化
Tests/                     核心回归测试
Scripts/                   构建、验证及打包脚本
```

运行核心测试及 Swift 6 严格并发类型检查：

```sh
./Scripts/test-core.sh
```

仅使用 Command Line Tools 时：

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools ./Scripts/test-core.sh
```

若 SDK 缺少 SwiftUI 宏插件，可通过 `SDKROOT` 指定本机已安装且兼容的 SDK。完整构建、签名、扩展与 ZIP 解包验证使用：

```sh
./Scripts/verify-local.sh
```

## 发布与协作

- [发布规范](docs/RELEASING.md)：版本号、标签、安装包及更新清单的发布顺序。
- [贡献指南](CONTRIBUTING.md)：开发检查、提交格式与 Pull Request 要求。
- [更新日志](CHANGELOG.md)：按版本记录用户可见变更。
- [问题反馈](https://github.com/heropml/Assistant/issues/new/choose)：提交缺陷或功能建议。

本仓库尚未声明开源许可证；公开可见不代表已授予开源许可。
