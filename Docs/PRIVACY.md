# Privacy

PlansBar is local-first and has no telemetry.

## Data access

- The user explicitly chooses one workspace root.
- PlansBar reads `docs/plans` files in place.
- PlansBar never edits, creates, moves, or deletes plan files.
- Repository paths and plan contents stay on the Mac.

## Local storage

UI preferences may be stored in `UserDefaults`. Workspace bookmarks, derived snapshots, and redacted diagnostics may be stored in Application Support. These files are local and can be recreated from the selected workspace.

## Network access

The macOS app does not require a service account, cloud backend, analytics endpoint, or bundled web server. Opening a GitHub link is an explicit user action.

## Diagnostics

Bug reports should omit plan contents, absolute paths, repository names, and command output unless the reporter has reviewed and redacted them.
