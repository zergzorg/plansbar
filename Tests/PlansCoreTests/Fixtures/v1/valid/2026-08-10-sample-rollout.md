# Sample rollout

Plan-Version: 1
Status: active
Created: 2026-08-10
Scope: Demonstrate deterministic v1 parsing

## Overview

Roll out a small synthetic change.

## Context

The fenced example below is documentation, not part of this plan's structure:

````md
# Nested example

Plan-Version: 1
Status: backlog
Created: 2026-08-09
Scope: Ignored example

## Overview

## Context

## Implementation Steps

- [ ] Fake nested step

## Validation Commands

```bash
true
```

## Acceptance Criteria

- The example is ignored.

## Risks / Open Questions

- None.
````

## Implementation Steps

### Task 1: Prepare the sample

- [x] Add the fixture.
- [x] Keep progress rounding deterministic.
- [ ] Verify the root-relative golden output.

## Validation Commands

```bash
plansbar lint . --json
```

## Acceptance Criteria

- Progress is two of three steps.
- The nested fake step is ignored.

## Risks / Open Questions

- None.
