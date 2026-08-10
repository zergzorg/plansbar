export type CreatePlanBucket = 'active' | 'backlog';

export function buildNextStepPrompt(planPath: string): string {
  return `Continue this plan. Read it in full and complete its next open step: ${planPath}`;
}

export function buildActivateBacklogPrompt(planPath: string): string {
  return `Move this backlog plan to active without losing context, then complete its first meaningful open step: ${planPath}`;
}

export function buildClosePlanPrompt(planPath: string): string {
  return `Review this plan against its validation and acceptance criteria. Close it only if the evidence passes: ${planPath}`;
}

export interface PortablePromptInput {
  title: string;
  repo: string;
  repoPath: string;
  absolutePlanPath: string;
  bucket: string;
  status: string;
  checkboxDone: number;
  checkboxTotal: number;
  nextStep: string | null;
}

export function buildPortablePrompt(input: PortablePromptInput): string {
  const progress = input.checkboxTotal > 0
    ? `${input.checkboxDone} of ${input.checkboxTotal} steps complete`
    : 'steps are not marked with checkboxes';
  const nextStep = input.nextStep ? `\nNext step: ${input.nextStep}` : '';

  return [
    input.nextStep ? 'Continue work on this plan.' : 'Review and finish this plan.',
    '',
    `Plan: ${input.absolutePlanPath}`,
    `Repository: ${input.repo} (${input.repoPath})`,
    `Status: ${input.bucket}${input.status ? ` / ${input.status}` : ''}`,
    `Progress: ${progress}`,
    `Title: ${input.title}${nextStep}`,
    '',
    input.nextStep
      ? 'Read the full plan, complete its next open step, update the checkbox, and briefly report what changed.'
      : 'Read the full plan, run its validation and acceptance checks, and report whether it is ready to close.'
  ].join('\n');
}

export function buildCreatePlanPrompt(input: {
  projectPath: string;
  title: string;
  description: string;
  bucket: CreatePlanBucket;
}): string {
  return [
    `Create a ${input.bucket} plan in this repository: ${input.projectPath}`,
    `Title: ${input.title}`,
    input.description ? `Context: ${input.description}` : '',
    'Follow the repository plan contract and keep the first open checkbox actionable.'
  ].filter(Boolean).join('\n');
}
