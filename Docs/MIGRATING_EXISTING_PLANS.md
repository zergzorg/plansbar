# Preparing an Existing Repository

PlansBar accepts one plan format: [Plan Format v1](PLAN_FORMAT_V1.md). A repository can live anywhere on disk, but the user must add its root explicitly.

## Repository states

- `ready`: required folders exist and all candidate plans pass v1 validation. No preparation prompt is generated.
- `missing_structure`: none of `docs/plans/{backlog,active,completed}` exist.
- `invalid_plans`: at least one candidate is not valid v1.
- `inaccessible`: the registered root is missing or unreadable. Re-add it or fix access before preparation.

PlansBar is read-only in every state. It can copy or hand off the prompt in [REPOSITORY_PREPARATION_AGENT_PROMPT.md](REPOSITORY_PREPARATION_AGENT_PROMPT.md); the selected agent performs any reviewed file changes.

## Required CLI gate

Manual review does not replace the PlansCore CLI gate. Check metadata order, filename/date agreement, bucket/status agreement, canonical section order, checkbox scope, completion evidence, and code fences, then run:

```bash
plansbar validate-repository --root <repository> --json
plansbar lint <repository> --json
```

Do not claim repository preparation complete unless both commands succeed.

## Safety rules

- Read repository instructions and inspect `git status` first.
- Preserve unrelated work and existing evidence.
- Do not invent dates, validation results, completed work, or scope.
- Keep ambiguous completed history in `MANUAL_REVIEW`.
- Do not commit or push without explicit authorization.
- Never paste real plan contents, absolute paths, private repository names, secrets, or raw command output into public issues or fixtures.
