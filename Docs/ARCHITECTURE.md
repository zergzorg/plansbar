# Architecture

## Public identity

- Product: PlansBar
- Repository: `zergzorg/plansbar`
- Bundle identifier: `io.github.zergzorg.plansbar`
- License: MIT
- Supported system: macOS 14 or later
- Distribution: reproducible local source build with ad-hoc signing

## Boundaries

PlansBar is a native menu bar app. The release bundle contains Swift code and resources only; it does not start Node.js, npm, a web server, or a process from a source checkout.

The user explicitly registers one or more repository roots, which may live in unrelated folders. PlansBar validates each root for `docs/plans/{backlog,active,completed}` and Plan Format v1, then reads valid plans in place. It does not search a parent workspace for repositories and does not edit, create, move, or delete plan files. Missing structure, invalid plans, and lifecycle changes are expressed as provider-neutral prompts and executed only by an agent selected by the user.

Preferences use `UserDefaults`. Per-repository bookmark data, derived snapshots, and redacted diagnostics belong in Application Support. PlansBar sends no telemetry.

## Package layout

```text
Sources/
├── PlansCore/
├── PlansBar/
└── plansbar-cli/
Tests/
└── PlansCoreTests/
```

`PlansCore` owns portable models and prompt generation. `PlansBar` owns AppKit/SwiftUI presentation. The optional dashboard remains source-installed and is not an app runtime dependency or a v1 release gate.

## Current implementation

`PlansCore` owns the strict-v1 parser, repository validator, redacted CLI reports, repository preparation prompt, stable repository identity, and versioned snapshot cache. The app stores independent repository bookmarks and the latest valid cache in Application Support, validates repositories off the main actor, and atomically publishes the cached or refreshed snapshot to SwiftUI. Missing structure and invalid plans stay visible as repository health cards; the app never mutates their files.

An FSEvents watcher on each root's `docs` rescans only the affected repository. The first scan publishes the active and backlog queue before the completed archive. Plan freshness comes from one `git log` per repository and falls back to file modification time when Git is missing or times out. Agent handoff opens Codex CLI or Claude Code CLI in Terminal only after `git status` reports a clean worktree; copying the prompt is always available.
