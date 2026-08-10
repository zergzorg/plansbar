# Unsafe HTML

Plan-Version: 1
Status: active
Created: 2026-08-10
Scope: Reject executable HTML

## Overview

<script>alert("not executed")</script>

## Context

This file is intentionally invalid.

## Implementation Steps

- [ ] Remove executable HTML.

## Validation Commands

Manual scenario: lint the file.

## Acceptance Criteria

- Executable HTML is rejected.

## Risks / Open Questions

- None.
