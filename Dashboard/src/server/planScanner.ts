import { execFileSync } from 'node:child_process';
import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync
} from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import type {
  BucketCounts,
  DashboardSnapshot,
  MetadataValue,
  MissingMetadataField,
  MissingValidationSection,
  PlanBucket,
  PlanTask,
  RepoSummary
} from '../shared/types.js';

const METADATA_MISSING = 'metadata_missing';
const BUCKETS: PlanBucket[] = ['active', 'backlog', 'completed'];
const EXCLUDED_FILES = new Set(['README.md', '.gitkeep', '.DS_Store']);
// `artifacts` — легальное место для companion-материалов плана (спецификации,
// макеты, выгрузки), которые сами планами не являются и в очередях не нужны.
const EXCLUDED_DIRS = new Set(['templates', 'temp_files', '.reviews', 'artifacts', 'assets']);

// Планы писались по разным шаблонам, поэтому проверочные секции признаются
// по историческим синонимам, а не только по каноническому заголовку.
const VALIDATION_COMMAND_SECTIONS = [
  'Validation Commands',
  'Testing Strategy',
  'Validation',
  'Проверк',
  'Валидац'
] as const;
const ACCEPTANCE_CRITERIA_SECTIONS = [
  'Acceptance Criteria',
  'Acceptance',
  'Outcome Contract',
  'Критерии приёмки',
  'Критерии приемки'
] as const;
const COMPLETION_NOTES_SECTIONS = [
  'Completion Notes',
  'Итоги реализации',
  'Итог реализации'
] as const;
const DEFAULT_STALE_DAYS = 30;

export interface ScanOptions {
  root?: string;
  staleDays?: number;
  now?: Date;
  getGitLastModified?: (repoPath: string, relativePath: string) => MetadataValue;
}

interface TaskEntity {
  entityPath: string;
  sourceFile: string | null;
}

export function scanPlansRoot(options: ScanOptions = {}): DashboardSnapshot {
  const root = path.resolve(options.root ?? path.join(homedir(), 'Code'));
  const staleDays = options.staleDays ?? DEFAULT_STALE_DAYS;
  const now = options.now ?? new Date();
  const getGitLastModified = options.getGitLastModified ?? readGitLastModified;
  const repositories = discoverPlanRepositories(root).map((repoPath) =>
    scanRepository(repoPath, staleDays, now, getGitLastModified)
  );

  repositories.sort((left, right) => left.name.localeCompare(right.name));

  return {
    generatedAt: now.toISOString(),
    root,
    staleDays,
    repositories,
    totals: repositories.reduce(
      (acc, repo) => {
        acc.repositories += 1;
        acc.active += repo.counts.active;
        acc.backlog += repo.counts.backlog;
        acc.completed += repo.counts.completed;
        acc.total += repo.counts.total;
        acc.active_open_steps += repo.active_open_steps;
        acc.stale_active += repo.stale_active;
        acc.metadata_issues += repo.metadata_issues;
        acc.validation_issues += repo.validation_issues;
        acc.completion_issues += repo.completion_issues;
        return acc;
      },
      {
        repositories: 0,
        active: 0,
        backlog: 0,
        completed: 0,
        total: 0,
        active_open_steps: 0,
        stale_active: 0,
        metadata_issues: 0,
        validation_issues: 0,
        completion_issues: 0
      }
    )
  };
}

export function discoverPlanRepositories(root: string): string[] {
  if (!existsSync(root)) {
    return [];
  }

  const repositories = new Set<string>();
  if (existsSync(path.join(root, 'docs', 'plans'))) {
    repositories.add(root);
  }

  for (const entry of safeReadDir(root)) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) {
      continue;
    }

    const repoPath = path.join(root, entry.name);
    if (existsSync(path.join(repoPath, 'docs', 'plans'))) {
      repositories.add(repoPath);
    }
  }

  return [...repositories];
}

function scanRepository(
  repoPath: string,
  staleDays: number,
  now: Date,
  getGitLastModified: (repoPath: string, relativePath: string) => MetadataValue
): RepoSummary {
  const repo = path.basename(repoPath);
  const tasks = BUCKETS.flatMap((bucket) =>
    collectBucketEntities(repoPath, bucket).map((entity) =>
      parseTask(repo, repoPath, bucket, entity, staleDays, now, getGitLastModified)
    )
  );

  tasks.sort(compareTasks);

  const counts = tasks.reduce<BucketCounts>(
    (acc, task) => {
      acc[task.bucket] += 1;
      acc.total += 1;
      return acc;
    },
    { active: 0, backlog: 0, completed: 0, total: 0 }
  );

  return {
    name: repo,
    path: repoPath,
    counts,
    active_open_steps: tasks
      .filter((task) => task.bucket === 'active')
      .reduce((sum, task) => sum + Math.max(task.checkbox_total - task.checkbox_done, 0), 0),
    stale_active: tasks.filter((task) => task.is_stale).length,
    metadata_issues: tasks.filter((task) => task.missing_metadata.length > 0).length,
    validation_issues: tasks.filter((task) => task.missing_validation_sections.length > 0).length,
    completion_issues: tasks.filter(
      (task) => task.completion_health === 'missing_completion_notes'
    ).length,
    tasks
  };
}

function collectBucketEntities(repoPath: string, bucket: PlanBucket): TaskEntity[] {
  const bucketDir = path.join(repoPath, 'docs', 'plans', bucket);
  if (!existsSync(bucketDir)) {
    return [];
  }

  const entries = safeReadDir(bucketDir).sort((left, right) => left.name.localeCompare(right.name));
  const entities: TaskEntity[] = [];
  const directoryStems = new Set<string>();
  const fileEntities = new Map<string, TaskEntity>();

  for (const entry of entries) {
    if (!entry.isDirectory() || isExcludedDir(entry.name)) {
      continue;
    }

    const entityPath = path.join(bucketDir, entry.name);
    const sourceFile = selectMainPlanFile(entityPath);
    if (!sourceFile) {
      continue;
    }

    directoryStems.add(entry.name);
    entities.push({
      entityPath,
      sourceFile
    });
  }

  for (const entry of entries) {
    if (!entry.isFile() || isExcludedFile(entry.name) || !isPlanSourceFile(entry.name)) {
      continue;
    }

    const stem = basenameWithoutKnownExtension(entry.name);
    if (directoryStems.has(stem)) {
      continue;
    }

    const entityPath = path.join(bucketDir, entry.name);
    const existing = fileEntities.get(stem);
    if (!existing || path.extname(entry.name).toLowerCase() === '.md') {
      fileEntities.set(stem, { entityPath, sourceFile: entityPath });
    }
  }

  return [...entities, ...fileEntities.values()];
}

function parseTask(
  repo: string,
  repoPath: string,
  bucket: PlanBucket,
  entity: TaskEntity,
  staleDays: number,
  now: Date,
  getGitLastModified: (repoPath: string, relativePath: string) => MetadataValue
): PlanTask {
  const filename = path.basename(entity.entityPath);
  const relativeEntityPath = toPosixPath(path.relative(repoPath, entity.entityPath));
  const content = entity.sourceFile ? safeReadFile(entity.sourceFile) : '';
  const title = extractTitle(content) ?? titleFromFilename(filename);
  const status = extractField(content, 'Status');
  const created = extractField(content, 'Created');
  const scope = extractField(content, 'Scope');
  const checkboxStats = countCheckboxes(content);
  const checkboxDone = checkboxStats.done;
  const checkboxTotal = checkboxStats.total;
  const progressPercent = checkboxTotal > 0 ? Math.round((checkboxDone / checkboxTotal) * 100) : null;
  const gitLastModified = getGitLastModified(repoPath, relativeEntityPath);
  const daysSinceModified = daysSince(gitLastModified, now);
  const missingMetadata = collectMissingMetadata(status, created, scope);
  const hasValidationCommands = hasAnySection(content, VALIDATION_COMMAND_SECTIONS);
  const hasAcceptanceCriteria = hasAnySection(content, ACCEPTANCE_CRITERIA_SECTIONS);
  const hasCompletionNotes = hasAnySection(content, COMPLETION_NOTES_SECTIONS);
  const missingValidationSections = collectMissingValidationSections(
    hasValidationCommands,
    hasAcceptanceCriteria
  );
  const staleReasons = collectStaleReasons(bucket, status, daysSinceModified, staleDays);
  const openSteps = extractOpenSteps(content);

  return {
    repo,
    repoPath,
    path: relativeEntityPath,
    absolutePath: entity.entityPath,
    sourceFile: entity.sourceFile,
    filename,
    bucket,
    date_from_filename: extractDateFromName(filename),
    title,
    status,
    created,
    scope,
    checkbox_total: checkboxTotal,
    checkbox_done: checkboxDone,
    progress_percent: progressPercent,
    has_validation_commands: hasValidationCommands,
    has_acceptance_criteria: hasAcceptanceCriteria,
    has_completion_notes: hasCompletionNotes,
    git_last_modified: gitLastModified,
    days_since_modified: daysSinceModified,
    timeline_date: resolveTimelineDate(bucket, filename, created, gitLastModified),
    next_open_step: openSteps[0] ?? null,
    open_steps: openSteps,
    missing_metadata: missingMetadata,
    missing_validation_sections: missingValidationSections,
    is_stale: staleReasons.length > 0,
    stale_reasons: staleReasons,
    completion_health:
      bucket === 'completed'
        ? hasCompletionNotes
          ? 'ok'
          : 'missing_completion_notes'
        : 'not_applicable'
  };
}

function selectMainPlanFile(taskDir: string): string | null {
  const dirName = path.basename(taskDir);
  for (const extension of ['.md', '.html']) {
    const sameName = path.join(taskDir, `${dirName}${extension}`);
    if (existsSync(sameName) && statSync(sameName).isFile()) {
      return sameName;
    }
  }

  for (const planFileName of ['plan.md', 'plan.html']) {
    const planFile = path.join(taskDir, planFileName);
    if (existsSync(planFile) && statSync(planFile).isFile()) {
      return planFile;
    }
  }

  const planLikeFiles = safeReadDir(taskDir)
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => isPlanSourceFile(name) && !isExcludedFile(name))
    .sort((left, right) => left.localeCompare(right));

  for (const fileName of planLikeFiles) {
    const candidate = path.join(taskDir, fileName);
    if (hasPlanMetadataSignal(safeReadFile(candidate))) {
      return candidate;
    }
  }

  return null;
}

function extractTitle(content: string): string | null {
  const match = content.match(/^#\s+(.+?)\s*$/m);
  if (match?.[1]?.trim()) {
    return match[1].trim();
  }

  const h1Match = content.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  if (h1Match?.[1]) {
    return normalizeHtmlText(h1Match[1]);
  }

  const titleMatch = content.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return titleMatch?.[1] ? normalizeHtmlText(titleMatch[1]) : null;
}

function extractField(content: string, field: 'Status' | 'Created' | 'Scope'): MetadataValue {
  for (const line of content.split(/\r?\n/)) {
    const normalized = line
      .trim()
      .replace(/<[^>]+>/g, '')
      .replace(/^[-*]\s+/, '');
    const match = normalized.match(
      new RegExp(`^\\*{0,2}${field}\\*{0,2}\\s*:\\*{0,2}\\s*(.+?)\\s*$`, 'i')
    );
    if (match?.[1]?.trim()) {
      return decodeHtmlEntities(match[1].trim());
    }
  }

  return METADATA_MISSING;
}

function extractDateFromName(filename: string): MetadataValue {
  return filename.match(/\d{4}-\d{2}-\d{2}/)?.[0] ?? METADATA_MISSING;
}

function extractOpenSteps(content: string): string[] {
  const steps: string[] = [];

  if (/<input\b/i.test(content)) {
    const htmlCheckbox = /<(label|li)[^>]*>\s*<input\b(?=[^>]*type=["']?checkbox["']?)(?![^>]*\bchecked\b)[^>]*>\s*([\s\S]*?)<\/\1>/gi;
    for (const match of content.matchAll(htmlCheckbox)) {
      const step = match[2] ? normalizeHtmlText(match[2]) : '';
      if (step && !steps.includes(step)) {
        steps.push(step);
      }
    }
  }

  for (const line of markdownContentLines(content)) {
    const openTask = line.match(/^\s*[-*]\s+\[ \]\s+(.+?)\s*$/);
    if (openTask?.[1]) {
      const step = openTask[1].replace(/\s+/g, ' ').trim();
      if (step && !steps.includes(step)) {
        steps.push(step);
      }
    }
  }

  return steps;
}

function hasAnySection(content: string, sectionTitles: readonly string[]): boolean {
  return sectionTitles.some((title) => hasSection(content, title));
}

function hasSection(content: string, sectionTitle: string): boolean {
  // Границы слова в JS опираются на латиницу, поэтому для кириллических
  // синонимов ищем вхождение в текст заголовка, а не \b-совпадение.
  const useWordBoundary = /^[\x20-\x7f]+$/.test(sectionTitle);
  const needle = escapeRegExp(sectionTitle);
  const boundary = useWordBoundary ? '\\b' : '';

  const htmlHeading = new RegExp(
    `<h[1-6][^>]*>[\\s\\S]*${boundary}${needle}${boundary}[\\s\\S]*<\\/h[1-6]>`,
    'i'
  );
  if (htmlHeading.test(content)) {
    return true;
  }

  return content
    .split(/\r?\n/)
    .some((line) =>
      new RegExp(`^#{1,6}\\s+.*${boundary}${needle}${boundary}`, 'i').test(line)
    );
}

function hasPlanMetadataSignal(content: string): boolean {
  return (
    extractField(content, 'Status') !== METADATA_MISSING ||
    extractField(content, 'Created') !== METADATA_MISSING ||
    extractField(content, 'Scope') !== METADATA_MISSING
  );
}

function collectMissingMetadata(
  status: MetadataValue,
  created: MetadataValue,
  scope: MetadataValue
): MissingMetadataField[] {
  const missing: MissingMetadataField[] = [];
  if (status === METADATA_MISSING) missing.push('Status');
  if (created === METADATA_MISSING) missing.push('Created');
  if (scope === METADATA_MISSING) missing.push('Scope');
  return missing;
}

function collectMissingValidationSections(
  hasValidationCommands: boolean,
  hasAcceptanceCriteria: boolean
): MissingValidationSection[] {
  const missing: MissingValidationSection[] = [];
  if (!hasValidationCommands) missing.push('Validation Commands');
  if (!hasAcceptanceCriteria) missing.push('Acceptance Criteria');
  return missing;
}

function collectStaleReasons(
  bucket: PlanBucket,
  status: MetadataValue,
  daysSinceModified: number | null,
  staleDays: number
): string[] {
  if (bucket !== 'active') {
    return [];
  }

  const reasons: string[] = [];
  const normalizedStatus = status.toLowerCase();

  if (status === METADATA_MISSING) {
    reasons.push('status_missing');
  }

  if (normalizedStatus === 'draft') {
    reasons.push('status_draft');
  }

  if (daysSinceModified !== null && daysSinceModified > staleDays) {
    reasons.push(`git_older_than_${staleDays}_days`);
  }

  return reasons;
}

function resolveTimelineDate(
  bucket: PlanBucket,
  filename: string,
  created: MetadataValue,
  gitLastModified: MetadataValue
): MetadataValue {
  if (bucket !== 'completed') {
    return METADATA_MISSING;
  }

  const dateFromFilename = extractDateFromName(filename);
  if (dateFromFilename !== METADATA_MISSING) return dateFromFilename;
  if (created !== METADATA_MISSING) return created;
  return gitLastModified;
}

export function readGitLastModified(repoPath: string, relativePath: string): MetadataValue {
  try {
    const result = execFileSync('git', ['-C', repoPath, 'log', '-1', '--format=%cI', '--', relativePath], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 2000
    }).trim();
    return result || METADATA_MISSING;
  } catch {
    return METADATA_MISSING;
  }
}

function daysSince(value: MetadataValue, now: Date): number | null {
  if (value === METADATA_MISSING) {
    return null;
  }

  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) {
    return null;
  }

  return Math.floor((now.getTime() - timestamp) / 86_400_000);
}

function compareTasks(left: PlanTask, right: PlanTask): number {
  if (left.bucket !== right.bucket) {
    return BUCKETS.indexOf(left.bucket) - BUCKETS.indexOf(right.bucket);
  }

  const leftDate = left.timeline_date !== METADATA_MISSING ? left.timeline_date : left.date_from_filename;
  const rightDate = right.timeline_date !== METADATA_MISSING ? right.timeline_date : right.date_from_filename;
  return rightDate.localeCompare(leftDate) || left.title.localeCompare(right.title);
}

function safeReadDir(dirPath: string) {
  try {
    return readdirSync(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }
}

function safeReadFile(filePath: string): string {
  try {
    return readFileSync(filePath, 'utf8');
  } catch {
    return '';
  }
}

function isExcludedFile(name: string): boolean {
  return EXCLUDED_FILES.has(name);
}

function isExcludedDir(name: string): boolean {
  return EXCLUDED_DIRS.has(name);
}

function titleFromFilename(filename: string): string {
  return path.basename(filename, path.extname(filename)) || 'Untitled';
}

function countCheckboxes(content: string): { done: number; total: number } {
  let markdownDone = 0;
  let markdownOpen = 0;

  for (const line of markdownContentLines(content)) {
    const taskCheckbox = line.match(/^\s*[-*]\s+\[([ xX])\]\s+/);
    if (!taskCheckbox) {
      continue;
    }

    if (taskCheckbox[1] === ' ') {
      markdownOpen += 1;
    } else {
      markdownDone += 1;
    }
  }

  const htmlInputs = content.match(/<input\b(?=[^>]*type=["']?checkbox["']?)[^>]*>/gi) ?? [];
  const htmlDone = htmlInputs.filter((input) => /\bchecked\b/i.test(input)).length;

  return {
    done: markdownDone + htmlDone,
    total: markdownDone + markdownOpen + htmlInputs.length
  };
}

function isPlanSourceFile(name: string): boolean {
  const extension = path.extname(name).toLowerCase();
  return extension === '.md' || extension === '.html';
}

function basenameWithoutKnownExtension(name: string): string {
  const extension = path.extname(name);
  return path.basename(name, extension);
}

function markdownContentLines(content: string): string[] {
  const lines: string[] = [];
  let inFence = false;

  for (const line of content.split(/\r?\n/)) {
    if (/^\s*```/.test(line)) {
      inFence = !inFence;
      continue;
    }

    if (!inFence) {
      lines.push(line);
    }
  }

  return lines;
}

function normalizeHtmlText(value: string): string {
  return decodeHtmlEntities(value.replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeHtmlEntities(value: string): string {
  return value
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function toPosixPath(value: string): string {
  return value.split(path.sep).join('/');
}
