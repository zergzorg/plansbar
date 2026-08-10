# PlansBar

[English](../../../README.md) · [Русский](../ru/README.md) · [简体中文](../zh-CN/README.md) · [Español](../es/README.md) · [Português do Brasil](../pt-BR/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Français](../fr/README.md) · [Deutsch](README.md)

> Übersetzungsentwurf. English is authoritative. Source docs version: 0.1.0.

PlansBar ist eine Open-Source-App für die macOS-Menüleiste. Sie zeigt ausführbare Markdown-Pläne aus lokalen Git-Repositories, liest Dateien nur und übergibt ausdrückliche Änderungen an Codex CLI, Claude Code CLI oder die Zwischenablage.

| Focus | Backlog |
| --- | --- |
| ![Focus-Ansicht mit simulierten Plänen für sample-api und mobile-app](../../assets/screenshots/focus.png) | ![Backlog-Ansicht mit einem simulierten Release-Health-Plan](../../assets/screenshots/backlog.png) |

Die Screenshots verwenden nur synthetische Daten für `sample-api` und `mobile-app`.

## Funktionen

- Repository-Wurzeln aus beliebigen Ordnern hinzufügen, ohne den übergeordneten Ordner zu durchsuchen.
- Ein einziges Pflichtformat verwenden: Plan Format v1.
- Zwischen Focus und Backlog wechseln, global suchen und lokal cachen.
- Aktionen über anbieterneutrale Prompts ausführen; die App ändert keine Plandateien.
- Keine Telemetrie, Konten oder eingebauter Webserver.

## Installation

Erforderlich sind macOS 14+, Git und Xcode Command Line Tools. Node.js und npm werden nicht benötigt.

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## Schnellstart

1. **Add Repository…** wählen und die Repository-Wurzel auswählen.
2. Diese interne Struktur beibehalten:

```text
docs/plans/{backlog,active,completed}
```

3. Falls das Repository nicht bereit ist, den preparation prompt kopieren.
4. Ask every time, Codex CLI, Claude Code CLI oder Copy only wählen.

Jeder Plan beginnt mit `Plan-Version: 1`. CLI-Prüfung:

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## Datenschutz und Beiträge

PlansBar speichert abgeleitete Daten nur auf dem Mac. Vor einer issue müssen Planinhalte, echte Namen, persönliche absolute Pfade und Zugangsdaten entfernt werden. Das English README und der [Formatvertrag](../../PLAN_FORMAT_V1.md) sind maßgeblich.

Fehler: [GitHub Issues](https://github.com/zergzorg/plansbar/issues). Releases: [GitHub Releases](https://github.com/zergzorg/plansbar/releases). Beiträge: [CONTRIBUTING.md](../../../CONTRIBUTING.md).
