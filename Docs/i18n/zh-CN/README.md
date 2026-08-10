# PlansBar

[English](../../../README.md) · [Русский](../ru/README.md) · [简体中文](README.md) · [Español](../es/README.md) · [Português do Brasil](../pt-BR/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> 翻译草稿。English is authoritative. Source docs version: 0.1.0.

PlansBar 是一个开源 macOS 菜单栏应用，用于查看本地 Git 仓库中的可执行 Markdown 计划。它只读取原文件，并把明确的修改任务交给 Codex CLI、Claude Code CLI 或剪贴板。

| Focus | Backlog |
| --- | --- |
| ![使用 sample-api 和 mobile-app 模拟计划的 Focus 视图](../../assets/screenshots/focus.png) | ![使用模拟发布健康计划的 Backlog 视图](../../assets/screenshots/backlog.png) |

截图只包含合成的 `sample-api` 和 `mobile-app` 数据。

## 功能

- 可从任意文件夹添加仓库根目录，不扫描父目录。
- 只支持一个必需格式：Plan Format v1。
- 提供 Focus、Backlog、跨仓库搜索和本地缓存。
- 通过与提供商无关的提示执行操作；应用本身不修改计划文件。
- 无遥测、无账号、无内置 Web 服务器。

## 安装

需要 macOS 14+、Git 和 Xcode Command Line Tools。应用不需要 Node.js 或 npm。

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## 快速开始

1. 选择 **Add Repository…** 并选取仓库根目录。
2. 保持以下内部结构：

```text
docs/plans/{backlog,active,completed}
```

3. 如果仓库尚未就绪，请复制 preparation prompt。
4. 选择 Ask every time、Codex CLI、Claude Code CLI 或 Copy only。

每个计划必须以 `Plan-Version: 1` 开头。CLI 验证：

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## 隐私与贡献

PlansBar 只在本机保存派生数据。提交 issue 前，请删除计划内容、真实仓库名、个人绝对路径和凭据。English README 和[格式规范](../../PLAN_FORMAT_V1.md)是权威来源。

问题：[GitHub Issues](https://github.com/zergzorg/plansbar/issues)。版本：[GitHub Releases](https://github.com/zergzorg/plansbar/releases)。贡献：[CONTRIBUTING.md](../../../CONTRIBUTING.md)。
