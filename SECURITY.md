# Security Policy

## Reporting

Use GitHub private vulnerability reporting for security issues. Do not open a public issue containing secrets, plan contents, absolute paths, private repository names, or unredacted diagnostics.

## Trust boundary

PlansBar treats plan contents as data. A plan cannot select an executable, add command-line flags, or trigger autonomous execution. Plan files remain read-only; lifecycle changes are delegated through an explicit prompt to an agent selected by the user.

The app has no telemetry or cloud backend. A local cache must be safe to delete and rebuild.
