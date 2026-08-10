export type PlanBucket = 'active' | 'backlog' | 'completed';

export type MetadataValue = string | 'metadata_missing';

export type ProgressPercent = number | null;

export type MissingMetadataField = 'Status' | 'Created' | 'Scope';

export type MissingValidationSection = 'Validation Commands' | 'Acceptance Criteria';

export interface PlanTask {
  repo: string;
  repoPath: string;
  path: string;
  absolutePath: string;
  sourceFile: string | null;
  filename: string;
  bucket: PlanBucket;
  date_from_filename: MetadataValue;
  title: string;
  status: MetadataValue;
  created: MetadataValue;
  scope: MetadataValue;
  checkbox_total: number;
  checkbox_done: number;
  progress_percent: ProgressPercent;
  has_validation_commands: boolean;
  has_acceptance_criteria: boolean;
  has_completion_notes: boolean;
  git_last_modified: MetadataValue;
  days_since_modified: number | null;
  timeline_date: MetadataValue;
  next_open_step: string | null;
  open_steps: string[];
  missing_metadata: MissingMetadataField[];
  missing_validation_sections: MissingValidationSection[];
  is_stale: boolean;
  stale_reasons: string[];
  completion_health: 'ok' | 'missing_completion_notes' | 'not_applicable';
}

export interface BucketCounts {
  active: number;
  backlog: number;
  completed: number;
  total: number;
}

export interface RepoSummary {
  name: string;
  path: string;
  counts: BucketCounts;
  active_open_steps: number;
  stale_active: number;
  metadata_issues: number;
  validation_issues: number;
  completion_issues: number;
  tasks: PlanTask[];
}

export interface DashboardSnapshot {
  generatedAt: string;
  root: string;
  staleDays: number;
  repositories: RepoSummary[];
  totals: BucketCounts & {
    repositories: number;
    active_open_steps: number;
    stale_active: number;
    metadata_issues: number;
    validation_issues: number;
    completion_issues: number;
  };
}

export interface SnapshotEvent {
  reason: string;
  snapshot: DashboardSnapshot;
}
