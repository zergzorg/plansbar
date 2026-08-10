import { describe, expect, it } from 'vitest';
import { findPlanHandoffCandidate, type PlanHandoffMatchContext } from './planHandoff';
import type { PlanTask } from './types';

function task(overrides: Partial<PlanTask> = {}): PlanTask {
  return {
    repo: 'sample-api',
    repoPath: '~/Code/sample-api',
    path: 'docs/plans/backlog/2026-07-17-new-idea.md',
    absolutePath: '~/Code/sample-api/docs/plans/backlog/2026-07-17-new-idea.md',
    sourceFile: null,
    filename: '2026-07-17-new-idea.md',
    bucket: 'backlog',
    date_from_filename: '2026-07-17',
    title: 'Новая идея',
    status: 'backlog',
    created: '2026-07-17',
    scope: 'Проверить workflow',
    checkbox_total: 0,
    checkbox_done: 0,
    progress_percent: 0,
    has_validation_commands: true,
    has_acceptance_criteria: true,
    has_completion_notes: false,
    git_last_modified: '2026-07-17',
    days_since_modified: 0,
    timeline_date: '2026-07-17',
    next_open_step: null,
    open_steps: [],
    missing_metadata: [],
    missing_validation_sections: [],
    is_stale: false,
    stale_reasons: [],
    completion_health: 'not_applicable',
    ...overrides
  };
}

function handoff(overrides: Partial<PlanHandoffMatchContext> = {}): PlanHandoffMatchContext {
  return {
    title: 'Новая идея',
    targetBucket: 'backlog',
    knownTaskKeys: [],
    ...overrides
  };
}

describe('findPlanHandoffCandidate', () => {
  it('matches a newly created plan by normalized title', () => {
    const candidate = task({ title: '  Новая идея!  ' });

    expect(findPlanHandoffCandidate([candidate], handoff())).toBe(candidate);
  });

  it('uses the only new plan when an agent refines the title', () => {
    const existing = task({ path: 'docs/plans/backlog/existing.md', title: 'Старый план' });
    const candidate = task({ title: 'Исполняемый inbox продуктовых идей' });

    expect(findPlanHandoffCandidate(
      [existing, candidate],
      handoff({ knownTaskKeys: [`${existing.repo}:${existing.path}`] })
    )).toBe(candidate);
  });

  it('does not guess when several unmatched plans appear', () => {
    expect(findPlanHandoffCandidate(
      [
        task({ path: 'docs/plans/backlog/first.md', title: 'Первая новая задача' }),
        task({ path: 'docs/plans/backlog/second.md', title: 'Вторая новая задача' })
      ],
      handoff()
    )).toBeNull();
  });

  it('matches a moved backlog plan by filename in active', () => {
    const candidate = task({
      bucket: 'active',
      path: 'docs/plans/active/2026-07-17-new-idea.md',
      title: 'Уточнённый active-план'
    });

    expect(findPlanHandoffCandidate(
      [candidate],
      handoff({
        title: 'Черновая идея',
        targetBucket: 'active',
        sourceFilename: '2026-07-17-new-idea.md'
      })
    )).toBe(candidate);
  });
});
