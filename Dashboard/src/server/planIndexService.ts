import chokidar, { type FSWatcher } from 'chokidar';
import { EventEmitter } from 'node:events';
import path from 'node:path';
import type { DashboardSnapshot } from '../shared/types.js';
import { scanPlansRoot } from './planScanner.js';

export interface PlanIndexServiceOptions {
  root: string;
  staleDays: number;
  watch?: boolean;
  rescanIntervalMs?: number;
}

type SnapshotListener = (snapshot: DashboardSnapshot, reason: string) => void;

export class PlanIndexService {
  private snapshot: DashboardSnapshot;
  private watcher: FSWatcher | null = null;
  private rescanTimer: NodeJS.Timeout | null = null;
  private debouncedRescan: NodeJS.Timeout | null = null;
  private readonly events = new EventEmitter();

  constructor(private readonly options: PlanIndexServiceOptions) {
    this.snapshot = scanPlansRoot({
      root: options.root,
      staleDays: options.staleDays
    });
  }

  async start(): Promise<void> {
    await this.rescan('startup');

    if (this.options.watch !== false) {
      this.startWatcher();
    }

    this.rescanTimer = setInterval(
      () => {
        void this.rescan('interval');
      },
      this.options.rescanIntervalMs ?? 60_000
    );
  }

  async stop(): Promise<void> {
    if (this.debouncedRescan) clearTimeout(this.debouncedRescan);
    if (this.rescanTimer) clearInterval(this.rescanTimer);
    if (this.watcher) await this.watcher.close();
  }

  getSnapshot(): DashboardSnapshot {
    return this.snapshot;
  }

  async rescan(reason: string): Promise<DashboardSnapshot> {
    this.snapshot = scanPlansRoot({
      root: this.options.root,
      staleDays: this.options.staleDays
    });
    this.events.emit('snapshot', this.snapshot, reason);
    return this.snapshot;
  }

  subscribe(listener: SnapshotListener): () => void {
    this.events.on('snapshot', listener);
    return () => {
      this.events.off('snapshot', listener);
    };
  }

  private startWatcher(): void {
    const patterns = [
      path.join(this.options.root, '*/docs/plans/active/**/*'),
      path.join(this.options.root, '*/docs/plans/backlog/**/*'),
      path.join(this.options.root, '*/docs/plans/completed/**/*'),
      path.join(this.options.root, 'docs/plans/active/**/*'),
      path.join(this.options.root, 'docs/plans/backlog/**/*'),
      path.join(this.options.root, 'docs/plans/completed/**/*')
    ];

    this.watcher = chokidar.watch(patterns, {
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 250,
        pollInterval: 100
      },
      ignored: (filePath) =>
        filePath.includes('/node_modules/') ||
        filePath.includes('/.git/') ||
        filePath.includes('/docs/plans/templates/') ||
        filePath.includes('/docs/plans/temp_files/') ||
        filePath.includes('/docs/plans/.reviews/')
    });

    this.watcher.on('all', () => {
      this.scheduleRescan();
    });
  }

  private scheduleRescan(): void {
    if (this.debouncedRescan) clearTimeout(this.debouncedRescan);
    this.debouncedRescan = setTimeout(() => {
      void this.rescan('watcher');
    }, 300);
  }
}
