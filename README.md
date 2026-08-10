# PlansBar

PlansBar is an open-source macOS menu bar app for working with Markdown plans across local Git repositories.

This repository starts with a clean publication boundary and a buildable source preview. The app will index repository roots explicitly added by the user from any folder, keep plan files read-only, and hand lifecycle changes or repository preparation to a user-selected coding agent. It does not collect telemetry.

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

- You explicitly choose each repository root; PlansBar does not search parent folders for repositories.
- PlansBar reads plan files in place and never edits or moves them.
- Derived state stays on the Mac.
- No telemetry, accounts, or cloud service.

See [Docs/PRIVACY.md](Docs/PRIVACY.md) and [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

## Plan repositories

PlansBar supports one executable-plan format: [Plan Format v1](Docs/PLAN_FORMAT_V1.md). Add each repository root explicitly and keep the same internal structure in every repository:

```text
docs/plans/{backlog,active,completed}
```

If that structure is missing or a candidate is not valid v1, PlansBar stays read-only and offers a [repository preparation prompt](Docs/REPOSITORY_PREPARATION_AGENT_PROMPT.md).

The same checks are available from the built CLI:

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
.build/release/plansbar lint /path/to/repository --json
```

## Repository layout

- `Sources/PlansBar` — macOS menu bar app.
- `Sources/PlansCore` — provider-neutral shared logic.
- `Sources/plansbar-cli` — command-line entry point.
- `Dashboard` — optional source-installed dashboard; it is not part of the app runtime or the v1 release gate.
- `Scripts` — local build and public-tree verification.

## Status

The source preview now includes a persistent repository picker, strict Plan Format v1 validation, a versioned local cache, cross-repository search, and preparation prompts for repositories that need setup or migration. Agent launching, filesystem watching, and release signing remain in progress.

## License

MIT. See [LICENSE](LICENSE).
