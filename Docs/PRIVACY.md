# Privacy

PlansBar is local-first and has no telemetry.

## Data access

- The user explicitly chooses each repository root; roots may live in unrelated folders.
- PlansBar does not crawl parent folders or discover neighboring repositories.
- PlansBar reads `docs/plans` files in place.
- PlansBar never edits, creates, moves, or deletes plan files.
- Repository paths and plan contents stay on the Mac.

## Local storage

UI preferences may be stored in `UserDefaults`. Repository bookmarks and the latest derived snapshot are stored in Application Support; redacted diagnostics may be stored there later. These files are local and can be recreated from the registered repositories.

## Network access

The macOS app does not require a service account, cloud backend, analytics endpoint, or bundled web server. Opening a GitHub link is an explicit user action.

## Diagnostics

Bug reports should omit plan contents, absolute paths, repository names, and command output unless the reporter has reviewed and redacted them.
