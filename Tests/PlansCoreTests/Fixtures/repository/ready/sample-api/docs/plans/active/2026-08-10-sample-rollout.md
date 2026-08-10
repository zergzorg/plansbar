# Sample rollout

Plan-Version: 1
Status: active
Created: 2026-08-10
Scope: Validate a ready synthetic repository

## Overview

Keep one valid plan in the ready fixture.

## Context

This fixture contains no personal data.

## Implementation Steps

### Task 1: Validate the repository

- [x] Add the synthetic plan.
- [ ] Run repository validation.

## Validation Commands

```bash
plansbar validate-repository --root . --json
```

## Acceptance Criteria

- The repository state is `ready`.

## Risks / Open Questions

- None.
