# PlansBar

[English](README.md) · [Русский](Docs/i18n/ru/README.md) · [简体中文](Docs/i18n/zh-CN/README.md) · [Español](Docs/i18n/es/README.md) · [Português do Brasil](Docs/i18n/pt-BR/README.md) · [日本語](Docs/i18n/ja/README.md) · [한국어](Docs/i18n/ko/README.md) · [Français](Docs/i18n/fr/README.md) · [Deutsch](Docs/i18n/de/README.md)

PlansBar is an open-source macOS menu bar app for working with executable Markdown plans across local Git repositories. It reads repositories in place, keeps plan files read-only, and hands explicit changes to Codex CLI, Claude Code CLI, or the clipboard.

| Focus | Backlog |
| --- | --- |
| ![Focus view with mocked sample-api and mobile-app plans](Docs/assets/screenshots/focus.png) | ![Backlog view with a mocked release-health plan](Docs/assets/screenshots/backlog.png) |

The screenshots use synthetic `sample-api` and `mobile-app` data. They contain no personal paths or private plan content.

## Features

- Add repository roots from any folder. PlansBar does not scan their parent directory.
- Use one required format: [Plan Format v1](Docs/PLAN_FORMAT_V1.md).
- Switch between active Focus work and the Backlog queue.
- Search every indexed plan by title, repository, or next step.
- Continue, activate, close, or create plans through provider-neutral prompts.
- Keep derived snapshots on the Mac. No telemetry, accounts, or bundled web server.

## Requirements

- macOS 14 or later
- Git
- Xcode Command Line Tools

Node.js and npm are not required by the macOS app.

## Install from source

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

The build is ad-hoc signed for local use. PlansBar does not publish a downloadable app bundle until Developer ID signing and notarization are available.

## Quick Start

1. Open PlansBar from the menu bar.
2. Choose **Add Repository…** and select a repository root.
3. Keep this structure inside the repository:

```text
docs/plans/{backlog,active,completed}
```

4. If the repository is not ready, copy or open its preparation prompt.
5. Choose **Ask every time**, **Codex CLI**, **Claude Code CLI**, or **Copy only** for plan actions.

PlansBar never edits, creates, moves, or deletes a plan file itself.

## Validate a repository

Every plan must start with `Plan-Version: 1` and follow the canonical English headings. Run the same checks from the CLI:

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
.build/release/plansbar lint /path/to/repository --json
```

See [the migration guide](Docs/MIGRATING_EXISTING_PLANS.md) and [repository preparation prompt](Docs/REPOSITORY_PREPARATION_AGENT_PROMPT.md).

## Agent handoff

PlansBar launches only an agent the user explicitly selects. Sessions open interactively in Terminal, in the selected repository root, without dangerous or non-interactive flags. Agent launch is blocked when the repository has uncommitted changes; copying the prompt remains available.

## Privacy and support

Read [the privacy boundary](Docs/PRIVACY.md) before sharing diagnostics. Bug reports must remove plan contents, real repository names, absolute personal paths, credentials, and unreviewed command output.

Use [GitHub Issues](https://github.com/zergzorg/plansbar/issues) for reproducible bugs and [GitHub Releases](https://github.com/zergzorg/plansbar/releases) for explicit update checks. PlansBar performs no background release polling.

## Status and contributing

Release milestones are `0.1` source preview, `0.2` source-built beta, and `1.0` source-built release. See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

PlansBar is licensed under the [MIT License](LICENSE).
