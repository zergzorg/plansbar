# PlansBar

[English](../../../README.md) · [Русский](../ru/README.md) · [简体中文](../zh-CN/README.md) · [Español](../es/README.md) · [Português do Brasil](../pt-BR/README.md) · [日本語](README.md) · [한국어](../ko/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> 翻訳ドラフトです。English is authoritative. Source docs version: 0.1.0.

PlansBar は、ローカル Git リポジトリの実行可能な Markdown プランを扱うオープンソースの macOS メニューバーアプリです。ファイルを読み取り専用で扱い、明示された変更を Codex CLI、Claude Code CLI、またはクリップボードへ渡します。

| Focus | Backlog |
| --- | --- |
| ![sample-api と mobile-app のモックプランを表示した Focus](../../assets/screenshots/focus.png) | ![リリース健全性のモックプランを表示した Backlog](../../assets/screenshots/backlog.png) |

スクリーンショットには合成した `sample-api` と `mobile-app` のデータだけを使用しています。

## 機能

- 任意のフォルダからリポジトリルートを追加し、親フォルダは走査しません。
- 必須形式は Plan Format v1 の一つだけです。
- Focus、Backlog、横断検索、ローカルキャッシュを提供します。
- プロバイダー非依存のプロンプトを使い、アプリ自体はプランを変更しません。
- テレメトリ、アカウント、内蔵 Web サーバーはありません。

## インストール

macOS 14+、Git、Xcode Command Line Tools が必要です。Node.js と npm は不要です。

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## クイックスタート

1. **Add Repository…** を選び、リポジトリルートを指定します。
2. 次の内部構造を維持します。

```text
docs/plans/{backlog,active,completed}
```

3. 未準備の場合は preparation prompt をコピーします。
4. Ask every time、Codex CLI、Claude Code CLI、Copy only から選びます。

各プランは `Plan-Version: 1` で始まります。CLI 検証：

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## プライバシーと貢献

派生データは Mac 内に保存されます。issue を公開する前に、プラン内容、実名、個人の絶対パス、認証情報を削除してください。English README と[形式契約](../../PLAN_FORMAT_V1.md)が正本です。

不具合：[GitHub Issues](https://github.com/zergzorg/plansbar/issues)。リリース：[GitHub Releases](https://github.com/zergzorg/plansbar/releases)。貢献：[CONTRIBUTING.md](../../../CONTRIBUTING.md)。
