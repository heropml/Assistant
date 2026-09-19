# 更新日志

采用按版本记录变更的格式，版本号遵循 `MAJOR.MINOR.PATCH`。本文件描述代码版本，是否已提供安装包以 GitHub Releases 为准。

## [Unreleased]

### 文档与仓库

- 规范项目介绍、安装说明、贡献指南及发布流程。
- 增加问题反馈和 Pull Request 模板。

## [1.0.0] - 2026-09-19

### 新增

- 可配置的 Finder 右键动作、分组、排序、收藏和上下文条件。
- 配置 JSON 导入导出、执行状态及最近执行记录。
- 窗口版本号、GitHub 更新检查、下载进度及大小和 SHA-256 校验。
- “右键助手 / Right-Click Assistant”本地化名称和中英文切换。
- ARM 安装包及更新清单生成脚本。

### 改进与修复

- 复用 Finder 文件信息和配置缓存。
- 等待全部后台动作完成后退出，避免并发任务被提前终止。
- 防止并发创建模板覆盖同名文件。
- 隔离剪切批次，避免旧粘贴任务清空新剪切内容。

### 验证

- 配置、执行器、更新及中英文回归测试。
- 主应用与 Finder 扩展的 Swift 6 严格并发类型检查。

[Unreleased]: https://github.com/heropml/Assistant/compare/4be3c0c...HEAD
[1.0.0]: https://github.com/heropml/Assistant/commit/4be3c0c
