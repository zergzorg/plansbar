# PlansBar

[English](../../../README.md) · [Русский](../ru/README.md) · [简体中文](../zh-CN/README.md) · [Español](../es/README.md) · [Português do Brasil](../pt-BR/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Français](README.md) · [Deutsch](../de/README.md)

> Traduction provisoire. English is authoritative. Source docs version: 0.1.0.

PlansBar est une application open source pour la barre de menus macOS. Elle affiche les plans Markdown exécutables de dépôts Git locaux, conserve les fichiers en lecture seule et transmet les changements explicites à Codex CLI, Claude Code CLI ou au presse-papiers.

| Focus | Backlog |
| --- | --- |
| ![Vue Focus avec des plans fictifs sample-api et mobile-app](../../assets/screenshots/focus.png) | ![Vue Backlog avec un plan fictif de santé de version](../../assets/screenshots/backlog.png) |

Les captures utilisent uniquement des données synthétiques `sample-api` et `mobile-app`.

## Fonctionnalités

- Ajoutez des racines de dépôts depuis n’importe quel dossier sans parcourir le dossier parent.
- Utilisez un seul format obligatoire : Plan Format v1.
- Basculez entre Focus et Backlog, recherchez partout et utilisez le cache local.
- Lancez des actions avec des prompts neutres ; l’application ne modifie pas les plans.
- Sans télémétrie, compte ni serveur web intégré.

## Installation

macOS 14+, Git et Xcode Command Line Tools sont requis. Node.js et npm ne sont pas nécessaires.

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## Démarrage rapide

1. Choisissez **Add Repository…** puis la racine du dépôt.
2. Conservez cette structure interne :

```text
docs/plans/{backlog,active,completed}
```

3. Si le dépôt n’est pas prêt, copiez le preparation prompt.
4. Choisissez Ask every time, Codex CLI, Claude Code CLI ou Copy only.

Chaque plan commence par `Plan-Version: 1`. Validation CLI :

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## Confidentialité et contribution

PlansBar conserve les données dérivées sur le Mac. Avant de publier une issue, retirez le contenu des plans, les vrais noms, les chemins personnels absolus et les identifiants. Le README English et le [contrat de format](../../PLAN_FORMAT_V1.md) font autorité.

Bugs : [GitHub Issues](https://github.com/zergzorg/plansbar/issues). Versions : [GitHub Releases](https://github.com/zergzorg/plansbar/releases). Contribuer : [CONTRIBUTING.md](../../../CONTRIBUTING.md).
