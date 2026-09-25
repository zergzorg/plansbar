# PlansBar Plan Format v1

This document is the normative PlansBar plan contract. Plan Format v1 is the only supported executable-plan format. Files without `Plan-Version: 1`, HTML plans, and plan directories must be prepared or migrated before PlansBar indexes them as plans.

## Repository structure

Users add repository roots explicitly. Repositories may live anywhere on disk; PlansBar does not discover repositories by walking a parent workspace.

Each registered root must contain:

```text
docs/plans/
├── README.md
├── backlog/
├── active/
└── completed/
```

Empty buckets may contain `.gitkeep`. `README.md`, hidden files, and content below `artifacts/`, `templates/`, `assets/`, `temp_files/`, or `.reviews/` are not plan candidates.

Repository validation has four states:

- `ready`: the required directories exist and every candidate is valid v1.
- `missing_structure`: none of the bucket directories exist. Git does not store empty directories, so a repository with at least one bucket is still indexed; absent buckets are listed in `missing_paths`.
- `invalid_plans`: the structure exists, but at least one candidate is not valid v1.
- `inaccessible`: the registered root is missing or cannot be read; re-add it or fix permissions.

PlansBar only reads repository files. For `missing_structure` and `invalid_plans` it may generate a preparation prompt, but it never creates directories or edits plans itself. `inaccessible` requires an access fix, not a preparation prompt.

## File and lifecycle

- Encoding: UTF-8 Markdown with LF line endings.
- Path: `docs/plans/{backlog,active,completed}/YYYY-MM-DD-slug.md`.
- The lowercase ASCII slug matches `[a-z0-9]+(?:-[a-z0-9]+)*`.
- The filename date equals `Created`.
- Moving a plan between buckets preserves its filename and `Created` date.
- A completed plan records its actual completion date in `Completed`.

## Metadata

Metadata appears after the H1 and before the first H2 in this exact order.

Backlog or active:

```md
# Title

Plan-Version: 1
Status: active
Created: 2026-08-10
Scope: One concrete area
```

Completed:

```md
# Title

Plan-Version: 1
Status: completed
Created: 2026-08-10
Completed: 2026-08-14
Scope: One concrete area
```

| Bucket | Allowed `Status` | Meaning |
| --- | --- | --- |
| `backlog` | `backlog` | Future work |
| `active` | `active` | Work in progress |
| `active` | `draft` | Valid, with a needs-decision warning |
| `active` | `blocked` | Valid, with a blocker warning |
| `active` | `paused` | Valid, with a resume-condition warning |
| `completed` | `completed` | Closed work with evidence |

Duplicate or unknown fields, wrong order, invalid dates, bucket/status mismatch, and metadata after the first H2 are errors. `Completed` is required only in `completed` and cannot be earlier than `Created`.

## Required sections

Backlog and active plans contain these canonical H2 headings in this relative order:

```md
## Overview
## Context
## Implementation Steps
## Validation Commands
## Acceptance Criteria
## Risks / Open Questions
```

Completed plans also contain `## Completion Notes` and may contain `## Validation Results` after risks.

- Progress and the next step use task-list rows only inside `## Implementation Steps`.
- The first open implementation checkbox is the next step.
- Checkboxes outside `## Implementation Steps` are errors. Acceptance and risks use ordinary bullets.
- `## Validation Commands` contains executable fenced commands or an explicitly labelled manual scenario.
- Completed plans have no open implementation checkboxes and contain factual, non-empty completion notes.
- Blocked or paused plans name the blocker or resume condition in risks.
- Raw executable HTML and scripts are forbidden.

## Fenced code blocks

Structural parsing ignores headings, metadata-like rows, and checkboxes inside closed fenced code blocks. A fence opens with at least three backticks or tildes and closes with the same character repeated at least as many times. Inline code remains ordinary text. An unclosed fence is `unclosed_code_fence`.

## Diagnostics

Every candidate yields either `parsed` or `invalid_plan`; malformed content never disappears silently. Stable error codes are:

```text
unclosed_code_fence
unsupported_plan_version
unparseable_plan
missing_required_metadata
duplicate_metadata_field
unknown_metadata_field
invalid_metadata_order
metadata_after_sections
invalid_date
invalid_filename
filename_created_mismatch
invalid_status
bucket_status_mismatch
completed_before_created
missing_required_section
duplicate_section
invalid_section_order
noncanonical_section
checkbox_outside_implementation_steps
completed_open_steps
empty_validation_commands
empty_completion_notes
raw_executable_html
```

Stable warnings are `status_draft`, `status_blocked`, and `status_paused`. Public diagnostics use root-relative paths and omit plan content by default.

## Translation-safe Quick Start

Keep these tokens unchanged in localized documentation: `Plan-Version: 1`, metadata keys, canonical H2 headings, paths, commands, status values, and diagnostic codes. Translate only their surrounding explanation.

1. Add the repository root in PlansBar.
2. Keep plans under `docs/plans/{backlog,active,completed}`.
3. Use `Plan-Version: 1` and the canonical English headings above.
4. If PlansBar reports `missing_structure` or `invalid_plans`, copy the repository preparation prompt and review the agent's diff.
