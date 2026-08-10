import type { PlanTask } from './types.js';

export interface MirrorGroup {
  /** Карточка, которую показываем вместо всей группы зеркал. */
  primary: PlanTask;
  /** Все копии плана, включая primary, отсортированные по имени репозитория. */
  mirrors: PlanTask[];
}

export interface DedupedPlans {
  tasks: PlanTask[];
  /** Ключ primary → группа, если у плана больше одной копии. */
  groups: Map<string, MirrorGroup>;
}

export function planTaskKey(task: PlanTask): string {
  return `${task.repo}:${task.path}`;
}

/**
 * Схлопывает копии одного плана из зеркальных клонов репозитория.
 * Один и тот же путь с одним заголовком в разных репозиториях — это один план,
 * а не две задачи, поэтому в представлении он должен занимать одну карточку.
 */
export function dedupeMirrors(tasks: PlanTask[]): DedupedPlans {
  const buckets = new Map<string, PlanTask[]>();

  for (const task of tasks) {
    const key = mirrorKey(task);
    const bucket = buckets.get(key);
    if (bucket) {
      bucket.push(task);
    } else {
      buckets.set(key, [task]);
    }
  }

  const deduped: PlanTask[] = [];
  const groups = new Map<string, MirrorGroup>();

  for (const bucket of buckets.values()) {
    const mirrors = bucket.slice().sort((left, right) => left.repo.localeCompare(right.repo));
    const primary = pickPrimary(mirrors);
    deduped.push(primary);

    if (mirrors.length > 1) {
      groups.set(planTaskKey(primary), { primary, mirrors });
    }
  }

  return { tasks: deduped, groups };
}

function mirrorKey(task: PlanTask): string {
  return `${task.path}|${normalizeTitle(task.title)}`;
}

/** Ведущей считаем самую свежую копию: она точнее отражает реальный прогресс. */
function pickPrimary(mirrors: PlanTask[]): PlanTask {
  return mirrors.reduce((best, candidate) => {
    const byDate = modifiedScore(candidate) - modifiedScore(best);
    if (byDate !== 0) return byDate > 0 ? candidate : best;

    const byProgress = (candidate.progress_percent ?? -1) - (best.progress_percent ?? -1);
    if (byProgress !== 0) return byProgress > 0 ? candidate : best;

    return best;
  });
}

function modifiedScore(task: PlanTask): number {
  const value = task.git_last_modified !== 'metadata_missing' ? task.git_last_modified : task.timeline_date;
  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function normalizeTitle(value: string): string {
  return value.trim().toLocaleLowerCase('ru-RU').replace(/\s+/g, ' ');
}
