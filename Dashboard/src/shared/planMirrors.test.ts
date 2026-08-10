import { describe, expect, it } from 'vitest';
import { dedupeMirrors, planTaskKey } from './planMirrors';
import type { PlanTask } from './types';

function task(overrides: Partial<PlanTask> = {}): PlanTask {
  return {
    repo: 'sample-api',
    repoPath: '~/Code/sample-api',
    path: 'docs/plans/active/2026-07-11-low-fidelity-artifact.md',
    absolutePath: '~/Code/sample-api/docs/plans/active/2026-07-11-low-fidelity-artifact.md',
    sourceFile: null,
    filename: '2026-07-11-low-fidelity-artifact.md',
    bucket: 'active',
    date_from_filename: '2026-07-11',
    title: 'Low-Fidelity Artifact',
    status: 'active',
    created: '2026-07-11',
    scope: 'Матрица элементов',
    checkbox_total: 10,
    checkbox_done: 3,
    progress_percent: 30,
    has_validation_commands: true,
    has_acceptance_criteria: true,
    has_completion_notes: false,
    git_last_modified: '2026-07-11',
    days_since_modified: 20,
    timeline_date: '2026-07-11',
    next_open_step: 'Собрать матрицу',
    open_steps: ['Собрать матрицу'],
    missing_metadata: [],
    missing_validation_sections: [],
    is_stale: false,
    stale_reasons: [],
    completion_health: 'not_applicable',
    ...overrides
  };
}

describe('dedupeMirrors', () => {
  it('схлопывает одинаковый план из зеркальных клонов в одну карточку', () => {
    const result = dedupeMirrors([
      task(),
      task({ repo: 'mobile-app', repoPath: '~/Code/mobile-app' })
    ]);

    expect(result.tasks).toHaveLength(1);
    expect(result.groups.size).toBe(1);
    expect(result.groups.get(planTaskKey(result.tasks[0]))?.mirrors.map((item) => item.repo))
      .toEqual(['mobile-app', 'sample-api']);
  });

  it('оставляет ведущей самую свежую копию', () => {
    const result = dedupeMirrors([
      task({ git_last_modified: '2026-07-11' }),
      task({ repo: 'mobile-app', repoPath: '~/Code/mobile-app', git_last_modified: '2026-07-25' })
    ]);

    expect(result.tasks[0].repo).toBe('mobile-app');
  });

  it('не объединяет планы с разными путями или заголовками', () => {
    const result = dedupeMirrors([
      task(),
      task({ repo: 'mobile-app', title: 'Другой план' }),
      task({ repo: 'mobile-app', path: 'docs/plans/active/other.md' })
    ]);

    expect(result.tasks).toHaveLength(3);
    expect(result.groups.size).toBe(0);
  });

  it('сохраняет исходный порядок первых вхождений', () => {
    const result = dedupeMirrors([
      task({ path: 'docs/plans/active/b.md', title: 'B' }),
      task({ path: 'docs/plans/active/a.md', title: 'A' }),
      task({ repo: 'mobile-app', path: 'docs/plans/active/b.md', title: 'B' })
    ]);

    expect(result.tasks.map((item) => item.title)).toEqual(['B', 'A']);
  });
});
