import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { scanPlansRoot } from './planScanner.js';

let tempRoots: string[] = [];

afterEach(() => {
  for (const root of tempRoots) {
    rmSync(root, { recursive: true, force: true });
  }
  tempRoots = [];
});

describe('scanPlansRoot', () => {
  it('scans file and directory plans while excluding service paths', () => {
    const root = createTempRoot();
    const repo = path.join(root, 'alpha');
    writePlan(
      repo,
      'active/2026-06-29-active-plan.md',
      [
        '# Active plan',
        '',
        'Status: draft',
        'Created: 2026-06-29',
        'Scope: active scan test',
        '',
        '## Validation Commands',
        '## Acceptance Criteria',
        '',
        '- `[ ]` — не начато',
        '```',
        '- [ ] Not a task inside code fence',
        '```',
        '- [x] Done',
        '- [ ] Next step',
        '- [ ] Later step'
      ].join('\n')
    );
    writePlan(repo, 'active/README.md', '# Not a task');
    writePlan(repo, 'active/templates/2026-06-29-skip.md', '# Skip');
    writePlan(repo, 'active/temp_files/2026-06-29-skip.md', '# Skip');
    writePlan(repo, 'active/.reviews/2026-06-29-skip.md', '# Skip');
    writePlan(repo, 'backlog/2026-06-20-folder-task/plan.md', '# Folder task\n\nCreated: 2026-06-20');
    writePlan(repo, 'backlog/2026-06-21-agent-bundle/PROD_RUN_ORDER.md', '# Agent run order\n\nRun scripts.');
    writePlan(
      repo,
      'backlog/2026-06-22-sibling-plan.md',
      '# Sibling plan\n\nStatus: backlog\nCreated: 2026-06-22\nScope: sibling survives invalid directory'
    );
    writePlan(repo, 'backlog/2026-06-22-sibling-plan/README.md', '# Support directory');
    writePlan(repo, 'completed/2026-05-01-done.md', '# Done\n\nStatus: done\nCreated: 2026-05-01\nScope: completed scan test');
    writePlan(path.join(root, 'beta'), 'docs/README.md', '# No plans here');

    const snapshot = scanPlansRoot({
      root,
      staleDays: 14,
      now: new Date('2026-06-30T00:00:00.000Z'),
      getGitLastModified: (_repoPath, relativePath) =>
        relativePath.includes('2026-06-29-active-plan')
          ? '2026-06-01T00:00:00.000Z'
          : 'metadata_missing'
    });

    expect(snapshot.repositories).toHaveLength(1);
    expect(snapshot.totals).toMatchObject({
      repositories: 1,
      active: 1,
      backlog: 2,
      completed: 1,
      total: 4
    });

    const [repoSummary] = snapshot.repositories;
    const active = repoSummary.tasks.find((task) => task.bucket === 'active');
    expect(active).toMatchObject({
      path: 'docs/plans/active/2026-06-29-active-plan.md',
      filename: '2026-06-29-active-plan.md',
      date_from_filename: '2026-06-29',
      title: 'Active plan',
      status: 'draft',
      created: '2026-06-29',
      scope: 'active scan test',
      checkbox_total: 3,
      checkbox_done: 1,
      progress_percent: 33,
      has_validation_commands: true,
      has_acceptance_criteria: true,
      is_stale: true,
      next_open_step: 'Next step',
      open_steps: ['Next step', 'Later step']
    });

    const backlog = repoSummary.tasks.find(
      (task) => task.path === 'docs/plans/backlog/2026-06-20-folder-task'
    );
    expect(backlog?.path).toBe('docs/plans/backlog/2026-06-20-folder-task');
    expect(backlog?.sourceFile?.endsWith('/plan.md')).toBe(true);
    expect(backlog?.missing_metadata).toEqual(['Status', 'Scope']);
    expect(repoSummary.tasks.some((task) => task.path.includes('agent-bundle'))).toBe(false);
    expect(repoSummary.tasks.some((task) => task.path === 'docs/plans/backlog/2026-06-22-sibling-plan.md')).toBe(
      true
    );

    const completed = repoSummary.tasks.find((task) => task.bucket === 'completed');
    expect(completed?.completion_health).toBe('missing_completion_notes');
  });

  it('prefers a markdown file matching the directory name over plan.md', () => {
    const root = createTempRoot();
    const repo = path.join(root, 'alpha');
    writePlan(repo, 'active/2026-06-30-choice/plan.md', '# Wrong source\n\nStatus: draft');
    writePlan(
      repo,
      'active/2026-06-30-choice/2026-06-30-choice.md',
      '# Preferred source\n\n**Status:** in_progress\n**Created:** 2026-06-30\n**Scope:** folder priority'
    );

    const snapshot = scanPlansRoot({
      root,
      now: new Date('2026-06-30T00:00:00.000Z'),
      getGitLastModified: () => 'metadata_missing'
    });

    const task = snapshot.repositories[0]?.tasks[0];
    expect(task?.title).toBe('Preferred source');
    expect(task?.status).toBe('in_progress');
    expect(task?.created).toBe('2026-06-30');
    expect(task?.scope).toBe('folder priority');
  });

  it('parses top-level HTML plans and deduplicates markdown/html siblings by stem', () => {
    const root = createTempRoot();
    const repo = path.join(root, 'alpha');
    writePlan(
      repo,
      'active/2026-06-30-html-plan.html',
      [
        '<!doctype html>',
        '<div class="app-shell" data-plan-id="2026-06-30-html-plan">',
        '<h1>HTML plan</h1>',
        '<span class="pill">Status: <strong id="plan-status">active</strong></span>',
        '<span class="pill">Created: 2026-06-30</span>',
        '<span class="pill">Scope: html parser</span>',
        '<h2>Validation Commands</h2>',
        '<h2>Acceptance Criteria</h2>',
        '<label><input type="checkbox" checked> Done html step</label>',
        '<li><input type="checkbox"> Open html step</li>',
        '<label><input type="checkbox"> Later html step</label>',
        '</div>'
      ].join('\n')
    );
    writePlan(
      repo,
      'active/2026-06-30-duplicate.md',
      '# Markdown wins\n\nStatus: active\nCreated: 2026-06-30\nScope: md source'
    );
    writePlan(
      repo,
      'active/2026-06-30-duplicate.html',
      '<h1>HTML duplicate</h1><span>Status: active</span>'
    );

    const snapshot = scanPlansRoot({
      root,
      now: new Date('2026-06-30T00:00:00.000Z'),
      getGitLastModified: () => 'metadata_missing'
    });

    expect(snapshot.totals.active).toBe(2);
    const html = snapshot.repositories[0]?.tasks.find((task) => task.filename.endsWith('.html'));
    expect(html).toMatchObject({
      title: 'HTML plan',
      status: 'active',
      created: '2026-06-30',
      scope: 'html parser',
      checkbox_total: 3,
      checkbox_done: 1,
      progress_percent: 33,
      has_validation_commands: true,
      has_acceptance_criteria: true,
      next_open_step: 'Open html step',
      open_steps: ['Open html step', 'Later html step']
    });

    const duplicate = snapshot.repositories[0]?.tasks.find((task) =>
      task.path.includes('2026-06-30-duplicate')
    );
    expect(duplicate?.filename).toBe('2026-06-30-duplicate.md');
    expect(duplicate?.title).toBe('Markdown wins');
  });

  it('preserves markdown markers inside metadata values', () => {
    const root = createTempRoot();
    const repo = path.join(root, 'alpha');
    writePlan(
      repo,
      'active/2026-06-30-stars.md',
      '# Stars\n\n**Status:** active\n**Created:** 2026-06-30\n**Scope:** monitor docs/plans/** across repos'
    );

    const snapshot = scanPlansRoot({
      root,
      now: new Date('2026-06-30T00:00:00.000Z'),
      getGitLastModified: () => 'metadata_missing'
    });

    expect(snapshot.repositories[0]?.tasks[0]?.scope).toBe('monitor docs/plans/** across repos');
  });

  it('recognises historical section synonyms for validation and acceptance', () => {
    const root = createTempRoot();
    writePlan(
      path.join(root, 'alpha'),
      'active/2026-08-09-legacy-template.md',
      [
        '# Legacy template plan',
        '',
        'Status: active',
        'Created: 2026-08-09',
        'Scope: план по старому шаблону',
        '',
        '## Testing Strategy',
        '- запустить npm test',
        '',
        '## Outcome Contract',
        '- поведение не меняется',
        '',
        '- [ ] Шаг'
      ].join('\n')
    );

    const snapshot = scanPlansRoot({
      root,
      now: new Date('2026-08-09T00:00:00.000Z'),
      getGitLastModified: () => 'metadata_missing'
    });
    const task = snapshot.repositories[0]?.tasks[0];

    expect(task?.has_validation_commands).toBe(true);
    expect(task?.has_acceptance_criteria).toBe(true);
    expect(task?.missing_validation_sections).toEqual([]);
  });

  it('recognises russian validation headings and completion notes', () => {
    const root = createTempRoot();
    writePlan(
      path.join(root, 'alpha'),
      'completed/2026-08-09-russian-headings.md',
      [
        '# Русские заголовки',
        '',
        'Status: completed',
        'Created: 2026-08-09',
        'Scope: проверка кириллических секций',
        '',
        '## Проверки',
        '- npm test',
        '',
        '## Критерии приёмки',
        '- всё зелёное',
        '',
        '## Итоги реализации',
        '- готово'
      ].join('\n')
    );

    const snapshot = scanPlansRoot({
      root,
      now: new Date('2026-08-09T00:00:00.000Z'),
      getGitLastModified: () => 'metadata_missing'
    });
    const task = snapshot.repositories[0]?.tasks[0];

    expect(task?.has_validation_commands).toBe(true);
    expect(task?.has_acceptance_criteria).toBe(true);
    expect(task?.completion_health).toBe('ok');
  });

  it('keeps companion artifacts out of the plan index', () => {
    const root = createTempRoot();
    const repo = path.join(root, 'alpha');
    writePlan(
      repo,
      'active/2026-08-09-real-plan.md',
      '# Real plan\n\nStatus: active\nCreated: 2026-08-09\nScope: настоящий план\n\n- [ ] Шаг'
    );
    writePlan(
      repo,
      'active/artifacts/2026-08-09-lofi-spec.md',
      '# Lofi spec\n\nStatus: active\nCreated: 2026-08-09\nScope: companion-артефакт'
    );

    const snapshot = scanPlansRoot({
      root,
      now: new Date('2026-08-09T00:00:00.000Z'),
      getGitLastModified: () => 'metadata_missing'
    });

    expect(snapshot.repositories[0]?.tasks.map((task) => task.title)).toEqual(['Real plan']);
  });
});

function createTempRoot(): string {
  const root = mkdtempSync(path.join(tmpdir(), 'plansbar-'));
  tempRoots.push(root);
  return root;
}

function writePlan(repo: string, relativePath: string, content: string): void {
  const fullPath = relativePath.startsWith('docs/')
    ? path.join(repo, relativePath)
    : path.join(repo, 'docs', 'plans', relativePath);
  mkdirSync(path.dirname(fullPath), { recursive: true });
  writeFileSync(fullPath, content, 'utf8');
}
