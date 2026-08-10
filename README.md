# PlansBar

PlansBar is an open-source macOS menu bar app for working with Markdown plans across local Git repositories.

This repository starts with a clean publication boundary and a buildable source preview. The app will index a workspace chosen by the user, keep plan files read-only, and hand lifecycle changes to a user-selected coding agent. It does not collect telemetry.

## Requirements

- macOS 14 or later
- Git
- Xcode Command Line Tools

Node.js and npm are not required by the macOS app.

## Build from source

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

The build is ad-hoc signed for local use. PlansBar does not publish a downloadable app bundle until Developer ID signing and notarization are available.

## Privacy boundary

- You choose the workspace root.
- PlansBar reads plan files in place and never edits or moves them.
- Derived state stays on the Mac.
- No telemetry, accounts, or cloud service.

See [Docs/PRIVACY.md](Docs/PRIVACY.md) and [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

## Repository layout

- `Sources/PlansBar` — macOS menu bar app.
- `Sources/PlansCore` — provider-neutral shared logic.
- `Sources/plansbar-cli` — command-line entry point.
- `Dashboard` — optional source-installed dashboard; it is not part of the app runtime or the v1 release gate.
- `Scripts` — local build and public-tree verification.

## Status

The initial public commit is a source preview. Workspace selection and the self-contained local index belong to the next implementation task.

## License

MIT. See [LICENSE](LICENSE).
