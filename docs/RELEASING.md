# 发布规范

## 版本与命名

- 用户版本遵循 `MAJOR.MINOR.PATCH`，例如 `1.0.1`；Git 标签为 `v1.0.1`。
- Xcode 主应用与扩展的 `MARKETING_VERSION` 必须一致，`CURRENT_PROJECT_VERSION` 每次交付递增。
- ARM 安装包命名为 `RightClickAssistant_v<版本号>_arm64.dmg`。
- Release 标题使用 `v<版本号> · 右键助手 / Right-Click Assistant`。
- Release 说明列出新增、修复、兼容要求、安装方法及校验值；只记录已实现和已验证的内容。

## 发布步骤

1. 更新版本、构建号和 `CHANGELOG.md`，完成测试及中英文、Finder 菜单验证。
2. 执行 `./Scripts/build-local.sh`，然后执行 `./Scripts/verify-local.sh`。
3. 执行 `./Scripts/package-update.sh "本次更新说明"`，生成 ARM DMG 与 `dist/latest.json`。
4. 核对 DMG 版本、arm64 架构、签名、文件大小及 SHA-256，将发布代码提交并推送。
5. 为已验证的提交创建 `v<版本号>` 标签和 GitHub Release，上传对应 DMG。
6. 确认安装包 URL 可公开下载，再将 `dist/latest.json` 复制到仓库根目录并提交、推送。
7. 核对公开清单中的版本、URL、架构、大小和摘要，使用旧版本验证检查与下载流程。

必须先上传安装包，再发布新版本清单。不要在同一版本下替换已发布安装包而保留旧校验值。首次发布也应确认仓库中已有清单与最终上传的安装包完全匹配。

## 更新清单

客户端读取 `https://raw.githubusercontent.com/heropml/Assistant/main/latest.json`。

| 字段 | 内容 |
| --- | --- |
| `version` | 正式版本号，如 `1.0.1` |
| `url_mac` | HTTPS 下载地址或地址数组，优先 GitHub |
| `arch_mac` | `arm64` |
| `sha256_mac` | 实际安装包 SHA-256 |
| `size_mac` | 实际字节数 |
| `notes` | 面向用户的更新说明 |

`Scripts/package-update.sh` 只生成本地文件，不会创建标签、Release 或推送代码。独立发布仓库可通过 `RCA_RELEASE_REPOSITORY=owner/repo` 指定，同时须同步修改应用 `Info.plist` 中的 `RCAUpdateManifestURL` 和 `RCAReleasesURL`。

## 分发说明

当前脚本使用 ad-hoc 签名，尚未使用 Developer ID 签名或 Apple 公证。Release 必须如实说明签名状态及系统、架构要求。
