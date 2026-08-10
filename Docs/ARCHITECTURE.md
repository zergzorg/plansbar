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

The user chooses one workspace root. PlansBar discovers plan files below that root and reads them in place. The app does not edit, create, move, or delete plan files. Lifecycle changes are expressed as provider-neutral prompts and executed only by an agent selected by the user.

Preferences use `UserDefaults`. Bookmark data, derived snapshots, and redacted diagnostics belong in Application Support. PlansBar sends no telemetry.

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

## Current source preview

The clean public repository and package boundaries are established first. Workspace access and the self-contained index are intentionally deferred to the next implementation task.
