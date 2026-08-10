import type { PlanBucket, PlanTask } from './types.js';

export interface PlanHandoffMatchContext {
  title: string;
  targetBucket: PlanBucket;
  knownTaskKeys: string[];
  sourceFilename?: string;
}

export function findPlanHandoffCandidate(
  tasks: PlanTask[],
  handoff: PlanHandoffMatchContext
): PlanTask | null {
  const newCandidates = tasks.filter((task) =>
    task.bucket === handoff.targetBucket
    && !handoff.knownTaskKeys.includes(planTaskKey(task))
  );
  const exactCandidate = newCandidates.find((task) =>
    (handoff.sourceFilename && task.filename === handoff.sourceFilename)
    || normalizePlanTitle(task.title) === normalizePlanTitle(handoff.title)
  );

  return exactCandidate ?? (newCandidates.length === 1 ? newCandidates[0] : null);
}

function planTaskKey(task: PlanTask): string {
  return `${task.repo}:${task.path}`;
}

function normalizePlanTitle(value: string): string {
  return value
    .trim()
    .toLocaleLowerCase('ru-RU')
    .replace(/ё/g, 'е')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}
