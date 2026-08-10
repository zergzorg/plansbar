import {
  AlertTriangle,
  ArrowRight,
  CalendarDays,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Circle,
  Clock3,
  Columns3,
  Command,
  Copy,
  FileText,
  FolderKanban,
  Keyboard,
  Link2,
  List,
  Lightbulb,
  PlayCircle,
  Plus,
  RefreshCw,
  Search,
  SlidersHorizontal,
  X
} from 'lucide-react';
import {
  Fragment,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode
} from 'react';
import {
  buildActivateBacklogPrompt,
  buildClosePlanPrompt,
  buildCreatePlanPrompt,
  buildNextStepPrompt,
  buildPortablePrompt,
  type CreatePlanBucket
} from '../shared/agentPrompt';
import { findPlanHandoffCandidate } from '../shared/planHandoff';
import { dedupeMirrors, type MirrorGroup } from '../shared/planMirrors';
import type { DashboardSnapshot, MetadataValue, PlanTask, RepoSummary, SnapshotEvent } from '../shared/types';

type RepoSelection = 'all' | string;
type WorkspaceView = 'focus' | 'active' | 'backlog' | 'completed';
type QualityFlag = 'stale' | 'metadata' | 'validation' | 'completion';
type SortMode = 'priority' | 'updated' | 'progress' | 'title';
type CheckpointState = 'done' | 'current' | 'issue' | 'idle';
type PresentationMode = 'board' | 'list' | 'timeline';
type BoardTone = 'todo' | 'progress' | 'review' | 'done';

interface UrlState {
  repo: RepoSelection;
  view: WorkspaceView;
  flags: QualityFlag[];
  search: string;
  sort: SortMode;
  mode: PresentationMode;
  mirrors: boolean;
  task: string | null;
}

interface ViewDefinition {
  key: WorkspaceView;
  label: string;
  description: string;
}

interface QualityDefinition {
  key: QualityFlag;
  label: string;
  hint: string;
}

type FocusGroupKey = 'ready' | 'attention' | 'continue';

/** Что именно положили в буфер: у каждой кнопки копирования свой отклик. */
type CopyKind = 'action' | 'agent' | 'path';

interface CopyFeedback {
  kind: CopyKind;
  ok: boolean;
}

interface PlanGroup {
  /** Фокус группирует по решению, архив — по месяцам, остальные представления — одной группой. */
  key: FocusGroupKey | 'all' | `month-${string}`;
  label: string;
  description: string;
  tasks: PlanTask[];
  startIndex: number;
}

interface BoardColumn {
  key: BoardTone;
  label: string;
  description: string;
  tasks: PlanTask[];
}

interface TimelineWeek {
  key: string;
  label: string;
  hint: string;
  tasks: PlanTask[];
}

interface PlanHandoff {
  kind: 'create' | 'activate';
  state: 'waiting' | 'found';
  repo: string;
  projectPath: string;
  title: string;
  targetBucket: CreatePlanBucket;
  knownTaskKeys: string[];
  sourceFilename?: string;
  matchedTaskKey?: string;
  createdAt: number;
}

interface CreatePlanHandoff {
  projectPath: string;
  title: string;
  bucket: CreatePlanBucket;
}

const PRESENTATION_MODES: Array<{
  key: PresentationMode;
  label: string;
  icon: typeof Columns3;
}> = [
  { key: 'board', label: 'Kanban', icon: Columns3 },
  { key: 'list', label: 'List', icon: List },
  { key: 'timeline', label: 'Timeline', icon: CalendarDays }
];

const WORK_VIEWS: ViewDefinition[] = [
  {
    key: 'focus',
    label: 'In progress',
    description: 'Active plans to close, resolve, or continue'
  },
  {
    key: 'backlog',
    label: 'Backlog',
    description: 'Future and deferred work'
  }
];

/** Архив живёт отдельно от рабочей навигации: его открывают по поводу, а не каждый день. */
const ARCHIVE_VIEW: ViewDefinition = {
  key: 'completed',
  label: 'Archive',
  description: 'Closed and verified plan history'
};

const QUALITY_FILTERS: QualityDefinition[] = [
  { key: 'stale', label: 'Stale', hint: 'No recent activity or the plan is still a draft' },
  { key: 'metadata', label: 'Missing context', hint: 'Status, Created, or Scope is missing' },
  { key: 'validation', label: 'Missing checks', hint: 'Validation Commands or Acceptance Criteria is missing' },
  { key: 'completion', label: 'Missing outcome', hint: 'Completed plan without Completion Notes' }
];

const VIEW_DEFINITIONS = [...WORK_VIEWS, ARCHIVE_VIEW];
const EMPTY_MIRROR_GROUPS: Map<string, MirrorGroup> = new Map();
/** Старые ссылки на quality-представления открываем как фильтр поверх всего индекса. */
const LEGACY_VIEW_FLAGS: Record<string, QualityFlag> = {
  stale: 'stale',
  metadata: 'metadata',
  validation: 'validation',
  completion: 'completion'
};
const PLAN_HANDOFF_STORAGE_KEY = 'plansbar:pending-handoff';
const PLAN_HANDOFF_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const CURRENT_TASK_STORAGE_KEY = 'plansbar:current-task';
const LAST_VISIT_STORAGE_KEY = 'plansbar:last-visit';
const EMPTY_SNAPSHOT: DashboardSnapshot = {
  generatedAt: new Date(0).toISOString(),
  root: '~/Code',
  staleDays: 30,
  repositories: [],
  totals: {
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
};

export function App() {
  const [initialUrlState] = useState<UrlState>(readUrlState);
  const [snapshot, setSnapshot] = useState<DashboardSnapshot>(EMPTY_SNAPSHOT);
  const [selectedRepo, setSelectedRepo] = useState<RepoSelection>(initialUrlState.repo);
  const [view, setView] = useState<WorkspaceView>(initialUrlState.view);
  const [qualityFlags, setQualityFlags] = useState<QualityFlag[]>(initialUrlState.flags);
  const [search, setSearch] = useState(initialUrlState.search);
  const [sortMode, setSortMode] = useState<SortMode>(initialUrlState.sort);
  const [presentationMode, setPresentationMode] = useState<PresentationMode>(initialUrlState.mode);
  const [showMirrors, setShowMirrors] = useState(initialUrlState.mirrors);
  const [selectedTaskKey, setSelectedTaskKey] = useState<string | null>(initialUrlState.task);
  const [isInspectorOpen, setIsInspectorOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isRescanning, setIsRescanning] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [copyFeedback, setCopyFeedback] = useState<CopyFeedback | null>(null);
  const [statusMessage, setStatusMessage] = useState('Connecting');
  const [planActionMessage, setPlanActionMessage] = useState('');
  const [planHandoff, setPlanHandoff] = useState<PlanHandoff | null>(readPlanHandoff);
  const [currentTaskKey, setCurrentTaskKey] = useState<string | null>(() => readStoredString(CURRENT_TASK_STORAGE_KEY));
  const [lastVisit] = useState<number>(() => Number(readStoredString(LAST_VISIT_STORAGE_KEY) ?? 0));
  const [isAgentBusy, setIsAgentBusy] = useState(false);
  const [showShortcuts, setShowShortcuts] = useState(false);
  const [showNavigator, setShowNavigator] = useState(false);
  const [showCreatePlan, setShowCreatePlan] = useState(false);
  const [createPlanDefaultBucket, setCreatePlanDefaultBucket] = useState<CreatePlanBucket>('backlog');
  const searchInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    void fetchSnapshot();

    const events = new EventSource('/api/events');
    events.addEventListener('snapshot', (event) => {
      const payload = JSON.parse((event as MessageEvent).data) as SnapshotEvent;
      setSnapshot(payload.snapshot);
      setStatusMessage(reasonLabel(payload.reason));
      setLoadError('');
      setIsLoading(false);
    });
    events.onerror = () => {
      setStatusMessage('Reconnecting');
    };

    return () => events.close();
  }, []);

  useEffect(() => {
    writeUrlState({
      repo: selectedRepo,
      view,
      flags: qualityFlags,
      search,
      sort: sortMode,
      mode: presentationMode,
      mirrors: showMirrors,
      task: selectedTaskKey
    });
  }, [presentationMode, qualityFlags, search, selectedRepo, selectedTaskKey, showMirrors, sortMode, view]);

  useEffect(() => {
    persistPlanHandoff(planHandoff);
  }, [planHandoff]);

  useEffect(() => {
    writeStoredString(CURRENT_TASK_STORAGE_KEY, currentTaskKey);
  }, [currentTaskKey]);

  // Отметку визита ставим один раз при загрузке: внутри сессии
  // индикатор «изменилось с прошлого захода» не должен гаснуть сам собой.
  useEffect(() => {
    writeStoredString(LAST_VISIT_STORAGE_KEY, String(Date.now()));
  }, []);

  useEffect(() => {
    if (!planHandoff || planHandoff.state === 'found') {
      return;
    }

    const repo = snapshot.repositories.find((item) => item.name === planHandoff.repo);
    const candidate = findPlanHandoffCandidate(repo?.tasks ?? [], planHandoff);

    if (candidate) {
      setPlanHandoff((current) => current
        ? { ...current, state: 'found', matchedTaskKey: taskKey(candidate) }
        : current);
    }
  }, [planHandoff, snapshot]);

  const selectedRepoSummary = useMemo(
    () => snapshot.repositories.find((repo) => repo.name === selectedRepo),
    [selectedRepo, snapshot.repositories]
  );

  useEffect(() => {
    if (selectedRepo === 'all' || snapshot.repositories.length === 0) {
      return;
    }

    if (!snapshot.repositories.some((repo) => repo.name === selectedRepo)) {
      setSelectedRepo('all');
    }
  }, [selectedRepo, snapshot.repositories]);

  const scopedRepos = useMemo(
    () => (selectedRepo === 'all' ? snapshot.repositories : selectedRepoSummary ? [selectedRepoSummary] : []),
    [selectedRepo, selectedRepoSummary, snapshot.repositories]
  );
  const rawScopedTasks = useMemo(() => scopedRepos.flatMap((repo) => repo.tasks), [scopedRepos]);
  const dedupedScope = useMemo(() => dedupeMirrors(rawScopedTasks), [rawScopedTasks]);
  const scopedTasks = showMirrors ? rawScopedTasks : dedupedScope.tasks;
  const mirrorGroups = showMirrors ? EMPTY_MIRROR_GROUPS : dedupedScope.groups;
  const mirrorSurplus = rawScopedTasks.length - dedupedScope.tasks.length;
  const viewCounts = useMemo(() => countViews(scopedTasks), [scopedTasks]);

  // Весь индекс без учёта выбранного репозитория — нужен поиску по планам.
  const indexTasks = useMemo(() => {
    const all = snapshot.repositories.flatMap((repo) => repo.tasks);
    return showMirrors ? all : dedupeMirrors(all).tasks;
  }, [showMirrors, snapshot.repositories]);

  // Счётчик обещает то, что покажет клик: число планов этого репозитория
  // в текущем представлении. Для «всех» — без зеркальных повторов.
  const repoCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const repo of snapshot.repositories) {
      counts.set(repo.name, repo.tasks.filter((task) => matchesView(task, view)).length);
    }
    return counts;
  }, [snapshot.repositories, view]);
  const allReposCount = useMemo(
    () => indexTasks.filter((task) => matchesView(task, view)).length,
    [indexTasks, view]
  );
  const flagCounts = useMemo(
    () => countQualityFlags(scopedTasks.filter((task) => matchesView(task, view))),
    [scopedTasks, view]
  );
  const visibleTasks = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase();
    const filtered = scopedTasks.filter((task) => {
      if (!matchesView(task, view)) {
        return false;
      }

      if (!qualityFlags.every((flag) => matchesQualityFlag(task, flag))) {
        return false;
      }

      if (!normalizedSearch) {
        return true;
      }

      return [task.title, task.path, task.repo, task.status, task.scope, ...task.open_steps]
        .join(' ')
        .toLowerCase()
        .includes(normalizedSearch);
    });

    return filtered.sort((left, right) => comparePlans(left, right, sortMode));
  }, [qualityFlags, scopedTasks, search, sortMode, view]);

  const planGroups = useMemo(() => buildPlanGroups(visibleTasks, view), [visibleTasks, view]);
  const boardColumns = useMemo(() => buildBoardColumns(visibleTasks), [visibleTasks]);
  // Kanban полезен, когда работа распределена. Если она собралась в одну колонку,
  // доска превращается в один длинный столбец и три пустых места.
  const isBoardDegenerate = useMemo(() => {
    const filled = boardColumns.filter((column) => column.tasks.length > 0);
    return visibleTasks.length > 0 && filled.length <= 1;
  }, [boardColumns, visibleTasks.length]);
  const effectiveMode: PresentationMode = presentationMode === 'board' && isBoardDegenerate
    ? 'list'
    : presentationMode;
  const navigationTasks = visibleTasks;
  const selectedTask = useMemo(() => {
    const byKey = selectedTaskKey
      ? navigationTasks.find((task) => taskKey(task) === selectedTaskKey)
      : null;
    return byKey ?? navigationTasks[0] ?? null;
  }, [navigationTasks, selectedTaskKey]);

  const currentView = getViewDefinition(view);

  // Закреплённый план ищем по всему индексу: он мог уехать в другое представление.
  const currentTask = useMemo(() => {
    if (!currentTaskKey) return null;
    const found = indexTasks.find((task) => taskKey(task) === currentTaskKey);
    return found && found.bucket !== 'completed' ? found : null;
  }, [currentTaskKey, indexTasks]);

  useEffect(() => {
    if (currentTaskKey && !currentTask) {
      setCurrentTaskKey(null);
    }
  }, [currentTask, currentTaskKey]);

  const changedTaskKeys = useMemo(
    () => collectChangedSince(scopedTasks, lastVisit),
    [lastVisit, scopedTasks]
  );

  useEffect(() => {
    function handleKeydown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      const isTextInput =
        target?.tagName === 'INPUT' ||
        target?.tagName === 'TEXTAREA' ||
        target?.tagName === 'SELECT' ||
        Boolean(target?.isContentEditable);

      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setShowNavigator((current) => !current);
        return;
      }

      if (event.key === 'Escape') {
        if (showCreatePlan) {
          setShowCreatePlan(false);
          return;
        }
        if (showNavigator) {
          setShowNavigator(false);
          return;
        }
        if (showShortcuts) {
          setShowShortcuts(false);
          return;
        }
        if (isInspectorOpen) {
          setIsInspectorOpen(false);
          return;
        }
        if (search) {
          setSearch('');
          searchInputRef.current?.blur();
          return;
        }
        if (target === searchInputRef.current) {
          searchInputRef.current?.blur();
        }
        return;
      }

      if (isTextInput) {
        return;
      }

      if (
        event.key.toLowerCase() === 'n'
        && !event.metaKey
        && !event.ctrlKey
        && !event.altKey
      ) {
        event.preventDefault();
        openCreatePlan();
        return;
      }

      if (event.key === '/') {
        event.preventDefault();
        searchInputRef.current?.focus();
        return;
      }

      if (event.key === '?') {
        event.preventDefault();
        setShowShortcuts(true);
        return;
      }

      if (event.key === 'Enter' && selectedTask) {
        event.preventDefault();
        setIsInspectorOpen(true);
        return;
      }

      if ((event.key.toLowerCase() === 'j' || event.key.toLowerCase() === 'k') && navigationTasks.length > 0) {
        event.preventDefault();
        const currentIndex = selectedTask
          ? navigationTasks.findIndex((task) => taskKey(task) === taskKey(selectedTask))
          : -1;
        const direction = event.key.toLowerCase() === 'j' ? 1 : -1;
        const nextIndex = Math.min(Math.max(currentIndex + direction, 0), navigationTasks.length - 1);
        const nextTask = navigationTasks[nextIndex];
        setSelectedTaskKey(taskKey(nextTask));
        window.requestAnimationFrame(() => {
          const targetKey = taskKey(nextTask);
          const targetElement = Array.from(document.querySelectorAll<HTMLElement>('[data-task-key]'))
            .find((element) => element.dataset.taskKey === targetKey);
          targetElement?.scrollIntoView({
            block: 'nearest',
            behavior: 'smooth'
          });
        });
      }
    }

    window.addEventListener('keydown', handleKeydown);
    return () => window.removeEventListener('keydown', handleKeydown);
  }, [isInspectorOpen, navigationTasks, search, selectedTask, showCreatePlan, showNavigator, showShortcuts]);

  async function fetchSnapshot() {
    setLoadError('');
    try {
      const response = await fetch('/api/snapshot');
      if (!response.ok) {
        throw new Error(`snapshot_${response.status}`);
      }
      setSnapshot(await response.json());
      setStatusMessage('Index updated');
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : 'snapshot_error');
      setStatusMessage('Offline');
    } finally {
      setIsLoading(false);
    }
  }

  async function rescan() {
    setIsRescanning(true);
    setLoadError('');
    try {
      const response = await fetch('/api/rescan', { method: 'POST' });
      if (!response.ok) {
        throw new Error(`rescan_${response.status}`);
      }
      setSnapshot(await response.json());
      setStatusMessage('Rescanned');
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : 'rescan_error');
      setStatusMessage('Scan failed');
    } finally {
      setIsRescanning(false);
    }
  }

  async function copyToClipboard(kind: CopyKind, text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopyFeedback({ kind, ok: true });
    } catch {
      setCopyFeedback({ kind, ok: false });
    }
    window.setTimeout(() => setCopyFeedback(null), 1800);
  }

  async function copyNextStep(task: PlanTask) {
    const absolutePlanPath = task.sourceFile ?? task.absolutePath;
    const prompt = task.bucket === 'backlog'
      ? buildActivateBacklogPrompt(absolutePlanPath)
      : isReadyToClose(task)
        ? buildClosePlanPrompt(absolutePlanPath)
        : buildNextStepPrompt(absolutePlanPath);

    await copyToClipboard('action', prompt);
  }

  /** Промпт без agent-specific commands: его вставляют в любого агента. */
  async function copyAgentPrompt(task: PlanTask) {
    await copyToClipboard('agent', buildPortablePrompt({
      title: task.title,
      repo: task.repo,
      repoPath: task.repoPath,
      absolutePlanPath: task.sourceFile ?? task.absolutePath,
      bucket: bucketLabel(task.bucket),
      status: task.status === 'metadata_missing' ? '' : task.status,
      checkboxDone: task.checkbox_done,
      checkboxTotal: task.checkbox_total,
      nextStep: task.next_open_step
    }));
  }

  async function copyPlanPath(task: PlanTask) {
    await copyToClipboard('path', task.sourceFile ?? task.absolutePath);
  }

  async function runNextStep(task: PlanTask) {
    const isActivation = task.bucket === 'backlog';
    setIsAgentBusy(true);
    setPlanActionMessage('');
    setCurrentTaskKey(taskKey(task));

    try {
      await copyNextStep(task);
      if (isActivation) {
        registerActivationHandoff(task);
      } else {
        setPlanActionMessage('Prompt copied');
      }
    } catch (error) {
      setPlanActionMessage(error instanceof Error ? error.message : 'copy_failed');
    } finally {
      setIsAgentBusy(false);
    }
  }

  function registerCreateHandoff(handoff: CreatePlanHandoff) {
    const repo = snapshot.repositories.find((item) => item.path === handoff.projectPath);
    if (!repo) return;

    setPlanHandoff({
      kind: 'create',
      state: 'waiting',
      repo: repo.name,
      projectPath: repo.path,
      title: handoff.title,
      targetBucket: handoff.bucket,
      createdAt: Date.now(),
      knownTaskKeys: repo.tasks
        .filter((task) => task.bucket === handoff.bucket)
        .map(taskKey)
    });
    setSelectedRepo(repo.name);
    setView(handoff.bucket);
    setPresentationMode('board');
    setSearch('');
    setSelectedTaskKey(null);
    setIsInspectorOpen(false);
    setShowCreatePlan(false);
  }

  function registerActivationHandoff(task: PlanTask) {
    const repo = snapshot.repositories.find((item) => item.name === task.repo);
    setPlanHandoff({
      kind: 'activate',
      state: 'waiting',
      repo: task.repo,
      projectPath: task.repoPath,
      title: task.title,
      targetBucket: 'active',
      createdAt: Date.now(),
      sourceFilename: task.filename,
      knownTaskKeys: repo?.tasks
        .filter((candidate) => candidate.bucket === 'active')
        .map(taskKey) ?? []
    });
    setSelectedRepo(task.repo);
    setView('active');
    setPresentationMode('board');
    setSearch('');
    setSelectedTaskKey(null);
    setIsInspectorOpen(false);
    setPlanActionMessage('');
  }

  function openHandoffPlan() {
    if (!planHandoff?.matchedTaskKey) return;
    setSelectedRepo(planHandoff.repo);
    setView(planHandoff.targetBucket);
    setSearch('');
    setSelectedTaskKey(planHandoff.matchedTaskKey);
    setIsInspectorOpen(true);
    setPlanHandoff(null);
  }

  function openCreatePlan(bucket: CreatePlanBucket = 'backlog') {
    setCreatePlanDefaultBucket(bucket);
    setShowCreatePlan(true);
  }

  function changeView(nextView: WorkspaceView) {
    setView(nextView);
    setSelectedTaskKey(null);
    setIsInspectorOpen(false);
  }

  function changeRepo(nextRepo: RepoSelection) {
    setSelectedRepo(nextRepo);
    setSelectedTaskKey(null);
    setIsInspectorOpen(false);
  }

  function toggleQualityFlag(flag: QualityFlag) {
    setQualityFlags((current) => (
      current.includes(flag) ? current.filter((item) => item !== flag) : [...current, flag]
    ));
    setSelectedTaskKey(null);
  }

  function selectTask(task: PlanTask) {
    setSelectedTaskKey(taskKey(task));
    setIsInspectorOpen(true);
    setPlanActionMessage('');
  }

  /** Открывает найденный план, переключая представление и репозиторий под него. */
  function revealTask(task: PlanTask) {
    if (!matchesView(task, view)) {
      setView(task.bucket === 'active' ? 'focus' : task.bucket);
    }
    if (selectedRepo !== 'all' && selectedRepo !== task.repo) {
      setSelectedRepo(task.repo);
    }
    setQualityFlags([]);
    setSearch('');
    selectTask(task);
  }

  return (
    <div className="app-shell">
      <a className="skip-link" href="#plan-ledger">Skip to plan list</a>

      <aside className="sidebar" aria-label="Plan navigation">
        <div className="brand-block">
          <span className="brand-mark" aria-hidden="true">
            <FolderKanban size={19} />
          </span>
          <div>
            <p className="utility-label">Plan index</p>
            <h1>Plans</h1>
          </div>
        </div>

        <button className="navigator-trigger" type="button" onClick={() => setShowNavigator(true)}>
          <Command size={15} aria-hidden="true" />
          <span>Go to…</span>
          <kbd>⌘K</kbd>
        </button>

        <nav className="view-navigation" aria-label="Views">
          <SidebarSection title="Work">
            {WORK_VIEWS.map((item) => (
              <ViewButton
                key={item.key}
                definition={item}
                count={viewCounts[item.key]}
                active={view === item.key}
                onClick={() => changeView(item.key)}
              />
            ))}
          </SidebarSection>
        </nav>

        {currentTask ? (
          <CurrentTaskCard
            task={currentTask}
            isAgentBusy={isAgentBusy}
            onOpen={() => revealTask(currentTask)}
            onRun={() => runNextStep(currentTask)}
            onRelease={() => setCurrentTaskKey(null)}
          />
        ) : null}

        <section className="repo-scope" aria-labelledby="repo-scope-title">
          <div className="sidebar-section-heading">
            <span id="repo-scope-title">Repositories</span>
            <small>{snapshot.repositories.length}</small>
          </div>
          <button
            className={selectedRepo === 'all' ? 'repo-button repo-button-active' : 'repo-button'}
            type="button"
            aria-pressed={selectedRepo === 'all'}
            onClick={() => changeRepo('all')}
          >
            <span>All repositories</span>
            <small>{allReposCount}</small>
          </button>
          <RepoList
            repositories={snapshot.repositories}
            counts={repoCounts}
            selectedRepo={selectedRepo}
            onSelect={changeRepo}
          />
          {mirrorSurplus > 0 || showMirrors ? (
            <button
              className={showMirrors ? 'mirror-toggle mirror-toggle-active' : 'mirror-toggle'}
              type="button"
              aria-pressed={showMirrors}
              onClick={() => setShowMirrors((current) => !current)}
              title="Mirror clones contain the same plans"
            >
              <Copy size={13} aria-hidden="true" />
              <span>{showMirrors ? 'Mirrors shown' : `Hidden copies: ${mirrorSurplus}`}</span>
            </button>
          ) : null}
        </section>

        <button
          className={view === 'completed' ? 'archive-link archive-link-active' : 'archive-link'}
          type="button"
          aria-pressed={view === 'completed'}
          onClick={() => changeView('completed')}
        >
          <FileText size={14} aria-hidden="true" />
          <span>{ARCHIVE_VIEW.label}</span>
          <small>{viewCounts.completed}</small>
        </button>

        <footer className="sidebar-footer">
          <span className="connection-dot" aria-hidden="true" />
          <span>{statusMessage}</span>
          <time>{formatTime(snapshot.generatedAt)}</time>
        </footer>
      </aside>

      <main className="workspace">
        <header className="workspace-header">
          <div className="mobile-brand">
            <div>
              <span className="brand-mark" aria-hidden="true"><FolderKanban size={17} /></span>
              <strong>Plans</strong>
            </div>
            <div className="mobile-brand-actions">
              <button type="button" onClick={() => setShowNavigator(true)} aria-label="Open navigator">
                <Command size={17} aria-hidden="true" />
              </button>
              <button type="button" onClick={rescan} disabled={isRescanning} aria-label="Refresh index">
                <RefreshCw className={isRescanning ? 'spin' : ''} size={17} aria-hidden="true" />
              </button>
              <button type="button" onClick={() => openCreatePlan()} aria-label="New idea">
                <Plus size={18} aria-hidden="true" />
              </button>
            </div>
          </div>

          <div className="mobile-scopes">
            <label>
              <span className="sr-only">View</span>
              <select value={view} onChange={(event) => changeView(event.target.value as WorkspaceView)}>
                {VIEW_DEFINITIONS.map((item) => (
                  <option key={item.key} value={item.key}>{item.label}</option>
                ))}
              </select>
            </label>
            <label>
              <span className="sr-only">Repository</span>
              <select value={selectedRepo} onChange={(event) => changeRepo(event.target.value)}>
                <option value="all">All repositories</option>
                {snapshot.repositories.map((repo) => (
                  <option key={repo.name} value={repo.name}>{repo.name}</option>
                ))}
              </select>
            </label>
          </div>

          <div className="header-primary">
            <div className="view-heading">
              <h2>{currentView.label}</h2>
              <p>
                {selectedRepo === 'all' ? 'All repositories' : selectedRepo}
                <span aria-hidden="true"> · </span>
                {visibleTasks.length} {pluralizePlans(visibleTasks.length)}
              </p>
            </div>
            <div className="header-actions">
              <button
                className="quiet-icon-button"
                type="button"
                onClick={() => setShowShortcuts(true)}
                aria-label="Show keyboard shortcuts"
                title="Keyboard shortcuts (?)"
              >
                <Keyboard size={18} aria-hidden="true" />
              </button>
              <button
                className="sync-button"
                type="button"
                onClick={rescan}
                disabled={isRescanning}
              >
                <RefreshCw className={isRescanning ? 'spin' : ''} size={17} aria-hidden="true" />
                <span>{isRescanning ? 'Scanning' : 'Refresh'}</span>
              </button>
              <button className="create-plan-button" type="button" onClick={() => openCreatePlan()}>
                <Lightbulb size={17} aria-hidden="true" />
                <span>New idea</span>
                <kbd>N</kbd>
              </button>
            </div>
          </div>
        </header>

        <section className="command-bar" aria-label="Mode, search, and sorting">
          <div className="presentation-tabs" role="tablist" aria-label="Plan presentation">
            {PRESENTATION_MODES.map((mode) => {
              const Icon = mode.icon;
              return (
                <button
                  className={presentationMode === mode.key ? 'presentation-tab presentation-tab-active' : 'presentation-tab'}
                  type="button"
                  role="tab"
                  aria-selected={presentationMode === mode.key}
                  key={mode.key}
                  onClick={() => setPresentationMode(mode.key)}
                >
                  <Icon size={16} aria-hidden="true" />
                  {mode.label}
                </button>
              );
            })}
          </div>
          <div className="quality-filters" role="group" aria-label="Quality filters">
            {QUALITY_FILTERS.map((filter) => {
              const isOn = qualityFlags.includes(filter.key);
              const count = flagCounts[filter.key];
              if (count === 0 && !isOn) return null;
              return (
                <button
                  className={isOn ? 'quality-chip quality-chip-active' : 'quality-chip'}
                  type="button"
                  aria-pressed={isOn}
                  title={filter.hint}
                  onClick={() => toggleQualityFlag(filter.key)}
                  key={filter.key}
                >
                  {filter.label}
                  <small>{count}</small>
                </button>
              );
            })}
            {qualityFlags.length > 0 ? (
              <button className="quality-chip quality-chip-reset" type="button" onClick={() => setQualityFlags([])}>
                <X size={13} aria-hidden="true" />
                Reset
              </button>
            ) : null}
          </div>

          <div className="command-tools">
            <label className="search-field">
              <Search size={17} aria-hidden="true" />
              <input
                ref={searchInputRef}
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search plans"
                aria-label="Search plans"
              />
              <kbd>/</kbd>
            </label>
            <label className="sort-field">
              <SlidersHorizontal size={16} aria-hidden="true" />
              <span className="sr-only">Sort</span>
              <select value={sortMode} onChange={(event) => setSortMode(event.target.value as SortMode)}>
                <option value="priority">Priority</option>
                <option value="updated">Updated</option>
                <option value="progress">Progress</option>
                <option value="title">Title</option>
              </select>
              <ChevronDown size={14} aria-hidden="true" />
            </label>
          </div>
        </section>

        {planHandoff ? (
          <PlanHandoffReceipt
            handoff={planHandoff}
            isRescanning={isRescanning}
            onDismiss={() => setPlanHandoff(null)}
            onOpen={openHandoffPlan}
            onRescan={rescan}
          />
        ) : null}

        {loadError ? (
          <div className="error-banner" role="alert">
            <AlertTriangle size={17} aria-hidden="true" />
            <span>Could not refresh the index: {loadError}</span>
            <button type="button" onClick={fetchSnapshot}>Retry</button>
          </div>
        ) : null}

        <div className="workspace-body">
          <section className={`plan-surface plan-surface-${effectiveMode}`} id="plan-ledger" aria-label="Plans">
            {isLoading ? (
              <LoadingState />
            ) : visibleTasks.length > 0 ? (
              effectiveMode === 'board' ? (
                <PlanBoard
                  columns={boardColumns}
                  mirrorGroups={mirrorGroups}
                  changedKeys={changedTaskKeys}
                  selectedTask={selectedTask}
                  onCreate={openCreatePlan}
                  onSelect={selectTask}
                  onRun={runNextStep}
                />
              ) : effectiveMode === 'list' ? (
                <div className="plan-groups">
                  {planGroups.map((group, index) => (
                    <PlanGroupSection
                      key={group.key}
                      group={group}
                      mirrorGroups={mirrorGroups}
                      changedKeys={changedTaskKeys}
                      collapsed={group.key.startsWith('month-') && index >= 3}
                      selectedTask={selectedTask}
                      onSelect={selectTask}
                      onRun={runNextStep}
                    />
                  ))}
                </div>
              ) : (
                <PlanTimeline
                  tasks={visibleTasks}
                  mirrorGroups={mirrorGroups}
                  changedKeys={changedTaskKeys}
                  selectedTask={selectedTask}
                  onSelect={selectTask}
                  onRun={runNextStep}
                />
              )
            ) : (
              <EmptyState
                view={view}
                search={search}
                hasFlags={qualityFlags.length > 0}
                onClearSearch={() => setSearch('')}
                onClearFlags={() => setQualityFlags([])}
              />
            )}
          </section>

          {isInspectorOpen ? (
            <button
              className="inspector-backdrop"
              type="button"
              aria-label="Close plan details"
              onClick={() => setIsInspectorOpen(false)}
            />
          ) : null}

          <aside className={isInspectorOpen ? 'inspector inspector-open' : 'inspector'} aria-label="Plan details">
            {selectedTask ? (
              <PlanInspector
                task={selectedTask}
                mirrorGroup={mirrorGroups.get(taskKey(selectedTask))}
                copyFeedback={copyFeedback}
                actionMessage={planActionMessage}
                isAgentBusy={isAgentBusy}
                onClose={() => setIsInspectorOpen(false)}
                onCopy={copyNextStep}
                onCopyAgentPrompt={copyAgentPrompt}
                onCopyPath={copyPlanPath}
                onRun={runNextStep}
              />
            ) : (
              <div className="inspector-empty">
                <Circle size={24} aria-hidden="true" />
                <h3>Select a plan</h3>
                <p>Next steps, checkpoints, and context will appear here.</p>
              </div>
            )}
          </aside>
        </div>
      </main>

      {showShortcuts ? <ShortcutsDialog onClose={() => setShowShortcuts(false)} /> : null}
      {showCreatePlan ? (
        <CreatePlanDialog
          repositories={snapshot.repositories}
          defaultRepo={selectedRepo}
          defaultBucket={createPlanDefaultBucket}
          onClose={() => setShowCreatePlan(false)}
          onHandoff={registerCreateHandoff}
        />
      ) : null}
      {showNavigator ? (
        <NavigatorDialog
          tasks={indexTasks}
          repositories={snapshot.repositories}
          viewCounts={viewCounts}
          repoCounts={repoCounts}
          selectedView={view}
          selectedRepo={selectedRepo}
          allReposCount={allReposCount}
          onView={(nextView) => {
            changeView(nextView);
            setShowNavigator(false);
          }}
          onRepo={(nextRepo) => {
            changeRepo(nextRepo);
            setShowNavigator(false);
          }}
          onTask={(task) => {
            revealTask(task);
            setShowNavigator(false);
          }}
          onClose={() => setShowNavigator(false)}
        />
      ) : null}
    </div>
  );
}

function PlanBoard({
  columns,
  mirrorGroups,
  changedKeys,
  selectedTask,
  onCreate,
  onSelect,
  onRun
}: {
  columns: BoardColumn[];
  mirrorGroups: Map<string, MirrorGroup>;
  changedKeys: Set<string>;
  selectedTask: PlanTask | null;
  onCreate: (bucket: CreatePlanBucket) => void;
  onSelect: (task: PlanTask) => void;
  onRun: (task: PlanTask) => void;
}) {
  // Пустая колонка не должна забирать четверть ширины у той, где лежит вся работа.
  const template = columns
    .map((column) => (column.tasks.length === 0 ? '132px' : 'minmax(220px, 1fr)'))
    .join(' ');

  return (
    <div className="kanban-board" style={{ '--kanban-template': template } as CSSProperties}>
      {columns.map((column) => (
        <section
          className={column.tasks.length === 0
            ? `kanban-column kanban-column-${column.key} kanban-column-quiet`
            : `kanban-column kanban-column-${column.key}`}
          key={column.key}
        >
          <header className="kanban-column-header">
            <div>
              <span className="kanban-status-dot" aria-hidden="true" />
              <h3 title={column.label}>{column.label}</h3>
              <small>{column.tasks.length}</small>
            </div>
            <button
              type="button"
              aria-label={column.key === 'progress'
                ? `Create an active plan in ${column.label}`
                : `Create a backlog idea in ${column.label}`}
              disabled={column.key === 'review' || column.key === 'done'}
              onClick={() => onCreate(column.key === 'progress' ? 'active' : 'backlog')}
              title={column.key === 'review' || column.key === 'done'
                ? 'A new plan starts in backlog or active'
                : column.key === 'progress'
                  ? 'Create active plan'
                  : 'Save new idea to backlog'}
            >
              <Plus size={16} aria-hidden="true" />
            </button>
          </header>
          <p className="kanban-column-description">{column.description}</p>
          <div className="kanban-card-list">
            {column.tasks.length > 0 ? column.tasks.map((task) => (
              <PlanCard
                key={taskKey(task)}
                task={task}
                active={selectedTask ? taskKey(task) === taskKey(selectedTask) : false}
                mirrorGroup={mirrorGroups.get(taskKey(task))}
                changed={changedKeys.has(taskKey(task))}
                onSelect={() => onSelect(task)}
                onRun={onRun}
              />
            )) : (
              <div className="kanban-empty">
                <CheckCircle2 size={18} aria-hidden="true" />
                <span>No plans</span>
              </div>
            )}
          </div>
        </section>
      ))}
    </div>
  );
}

function PlanCard({
  task,
  active,
  mirrorGroup,
  changed,
  onSelect,
  onRun
}: {
  task: PlanTask;
  active: boolean;
  mirrorGroup: MirrorGroup | undefined;
  changed: boolean;
  onSelect: () => void;
  onRun: (task: PlanTask) => void;
}) {
  return (
    <div className={active ? 'plan-card plan-card-active' : 'plan-card'}>
      <button
        className="plan-card-surface"
        type="button"
        data-task-key={taskKey(task)}
        aria-current={active ? 'true' : undefined}
        onClick={onSelect}
      >
        <div className="plan-card-title-line">
          <strong>{task.title}</strong>
          <span className="plan-card-marks">
            <ChangedDot changed={changed} />
            <MirrorBadge group={mirrorGroup} />
          </span>
        </div>
        <p className="plan-card-step">{rowInstruction(task)}</p>
        <ProgressBar task={task} />
        <footer>
          <span className="plan-repo-chip">{task.repo}</span>
          <span className="plan-card-facts">
            <span>{progressLabel(task)}</span>
            <span aria-hidden="true">·</span>
            <span>{relativeModified(task)}</span>
          </span>
          <SignalBadge signal={planSignal(task)} />
        </footer>
      </button>
      <QuickRunButton task={task} onRun={onRun} />
    </div>
  );
}

function PlanTimeline({
  tasks,
  mirrorGroups,
  changedKeys,
  selectedTask,
  onSelect,
  onRun
}: {
  tasks: PlanTask[];
  mirrorGroups: Map<string, MirrorGroup>;
  changedKeys: Set<string>;
  selectedTask: PlanTask | null;
  onSelect: (task: PlanTask) => void;
  onRun: (task: PlanTask) => void;
}) {
  const weeks = useMemo(() => buildTimelineWeeks(tasks), [tasks]);
  // Граница между тем, что случилось с прошлого захода, и тем, что было до него.
  const quietFrom = useMemo(() => {
    if (changedKeys.size === 0) return -1;
    return weeks.findIndex((week) => week.tasks.every((task) => !changedKeys.has(taskKey(task))));
  }, [changedKeys, weeks]);

  return (
    <div className="timeline-view">
      {weeks.map((week, index) => (
        <Fragment key={week.key}>
          {index === quietFrom && index > 0 ? (
            <p className="timeline-divider">Before your last visit</p>
          ) : null}
          <section className="timeline-week" aria-label={week.label}>
            <header className="timeline-week-heading">
              <div>
                <h3>{week.label}</h3>
                <p>{week.hint}</p>
              </div>
              <span>{week.tasks.length}</span>
            </header>
            <div className="timeline-entries">
              {week.tasks.map((task) => {
                const isActive = selectedTask ? taskKey(task) === taskKey(selectedTask) : false;
                return (
                  <div
                    className={isActive ? 'timeline-entry timeline-entry-active' : 'timeline-entry'}
                    key={taskKey(task)}
                  >
                    <button
                      className="timeline-entry-surface"
                      type="button"
                      data-task-key={taskKey(task)}
                      aria-current={isActive ? 'true' : undefined}
                      onClick={() => onSelect(task)}
                    >
                      <span className={`timeline-marker timeline-marker-${boardStage(task)}`} aria-hidden="true" />
                      <div className="timeline-entry-body">
                        <div className="timeline-entry-title">
                          <ChangedDot changed={changedKeys.has(taskKey(task))} />
                          <strong>{task.title}</strong>
                          <MirrorBadge group={mirrorGroups.get(taskKey(task))} />
                        </div>
                        <p>{rowInstruction(task)}</p>
                      </div>
                      <div className="timeline-entry-meta">
                        <span className="plan-repo-chip">{task.repo}</span>
                        <SignalBadge signal={planSignal(task)} />
                      </div>
                    </button>
                    <QuickRunButton task={task} onRun={onRun} />
                  </div>
                );
              })}
            </div>
          </section>
        </Fragment>
      ))}
    </div>
  );
}

/** Закреплённая работа: возврат к плану без повторного сканирования списка. */
function CurrentTaskCard({
  task,
  isAgentBusy,
  onOpen,
  onRun,
  onRelease
}: {
  task: PlanTask;
  isAgentBusy: boolean;
  onOpen: () => void;
  onRun: () => void;
  onRelease: () => void;
}) {
  return (
    <section className="current-task" aria-label="Current plan">
      <div className="current-task-heading">
        <span className="utility-label">In progress</span>
        <button type="button" onClick={onRelease} aria-label="Unpin plan">
          <X size={13} aria-hidden="true" />
        </button>
      </div>
      <button className="current-task-body" type="button" onClick={onOpen}>
        <strong>{task.title}</strong>
        <small>{task.repo}</small>
        <p>{rowInstruction(task)}</p>
        <ProgressBar task={task} />
      </button>
      <button
        className="current-task-run"
        type="button"
        onClick={onRun}
        disabled={isAgentBusy || !isMarkdownPlan(task)}
      >
        <PlayCircle size={15} aria-hidden="true" />
        {isAgentBusy ? 'Copying' : 'Continue'}
      </button>
    </section>
  );
}

function ChangedDot({ changed }: { changed: boolean }) {
  if (!changed) return null;
  return <i className="changed-dot" title="Changed since your last visit" aria-label="Changed since last visit" />;
}

function MirrorBadge({ group }: { group: MirrorGroup | undefined }) {
  if (!group) return null;
  const repos = group.mirrors.map((mirror) => mirror.repo).join(', ');
  return (
    <span className="mirror-badge" title={`Same file in: ${repos}`}>
      <Copy size={11} aria-hidden="true" />
      ×{group.mirrors.length}
    </span>
  );
}

function QuickRunButton({ task, onRun }: { task: PlanTask; onRun: (task: PlanTask) => void }) {
  if (!isMarkdownPlan(task)) return null;
  const label = primaryActionLabel(task);
  return (
    <button
      className="quick-run"
      type="button"
      title={label}
      aria-label={`${label}: ${task.title}`}
      onClick={(event) => {
        event.stopPropagation();
        onRun(task);
      }}
    >
      <PlayCircle size={16} aria-hidden="true" />
    </button>
  );
}

function SidebarSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="sidebar-section">
      <div className="sidebar-section-heading"><span>{title}</span></div>
      <div className="sidebar-section-items">{children}</div>
    </section>
  );
}

function ViewButton({
  definition,
  count,
  active,
  onClick
}: {
  definition: ViewDefinition;
  count: number;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={active ? 'view-button view-button-active' : 'view-button'}
      type="button"
      aria-pressed={active}
      onClick={onClick}
    >
      <span>{definition.label}</span>
      <small>{count}</small>
    </button>
  );
}

/** Репозитории без планов в текущем представлении прячем под раскрывашку. */
function RepoList({
  repositories,
  counts,
  selectedRepo,
  onSelect
}: {
  repositories: RepoSummary[];
  counts: Map<string, number>;
  selectedRepo: RepoSelection;
  onSelect: (repo: RepoSelection) => void;
}) {
  const [showEmpty, setShowEmpty] = useState(false);
  const withWork = repositories.filter((repo) => (counts.get(repo.name) ?? 0) > 0 || repo.name === selectedRepo);
  const empty = repositories.filter((repo) => !withWork.includes(repo));

  return (
    <div className="repo-list">
      {withWork.map((repo) => (
        <RepoButton
          key={repo.name}
          repo={repo}
          count={counts.get(repo.name) ?? 0}
          active={selectedRepo === repo.name}
          onClick={() => onSelect(repo.name)}
        />
      ))}

      {empty.length > 0 ? (
        <>
          <button className="repo-more" type="button" aria-expanded={showEmpty} onClick={() => setShowEmpty((v) => !v)}>
            <ChevronDown size={13} className={showEmpty ? 'repo-more-open' : ''} aria-hidden="true" />
            <span>No plans here</span>
            <small>{empty.length}</small>
          </button>
          {showEmpty
            ? empty.map((repo) => (
              <RepoButton
                key={repo.name}
                repo={repo}
                count={0}
                active={selectedRepo === repo.name}
                onClick={() => onSelect(repo.name)}
              />
            ))
            : null}
        </>
      ) : null}
    </div>
  );
}

function RepoButton({
  repo,
  count,
  active,
  onClick
}: {
  repo: RepoSummary;
  count: number;
  active: boolean;
  onClick: () => void;
}) {
  const issueCount = repo.stale_active + repo.metadata_issues + repo.validation_issues + repo.completion_issues;
  return (
    <button
      className={active ? 'repo-button repo-button-active' : 'repo-button'}
      type="button"
      aria-pressed={active}
      onClick={onClick}
    >
      <span>
        {repo.name}
        {issueCount > 0 ? <i className="repo-issue-dot" aria-hidden="true" title={`${issueCount} quality signals`} /> : null}
      </span>
      <small>{count}</small>
    </button>
  );
}

function PlanGroupSection({
  group,
  mirrorGroups,
  changedKeys,
  collapsed,
  selectedTask,
  onSelect,
  onRun
}: {
  group: PlanGroup;
  mirrorGroups: Map<string, MirrorGroup>;
  changedKeys: Set<string>;
  collapsed: boolean;
  selectedTask: PlanTask | null;
  onSelect: (task: PlanTask) => void;
  onRun: (task: PlanTask) => void;
}) {
  const isCollapsible = group.key.startsWith('month-');
  const [isOpen, setIsOpen] = useState(!collapsed);

  if (isCollapsible && !isOpen) {
    return (
      <section className="plan-group plan-group-collapsed">
        <button className="plan-group-heading" type="button" aria-expanded={false} onClick={() => setIsOpen(true)}>
          <div>
            <h3>{group.label}</h3>
            <p>{group.description}</p>
          </div>
          <span><ChevronDown size={15} aria-hidden="true" /></span>
        </button>
      </section>
    );
  }

  return (
    <section className={`plan-group plan-group-${group.key}`} aria-labelledby={`plan-group-${group.key}`}>
      {group.key !== 'all' ? (
        isCollapsible ? (
          <button className="plan-group-heading" type="button" aria-expanded onClick={() => setIsOpen(false)}>
            <div>
              <h3 id={`plan-group-${group.key}`}>{group.label}</h3>
              <p>{group.description}</p>
            </div>
            <span><ChevronDown size={15} className="repo-more-open" aria-hidden="true" /></span>
          </button>
        ) : (
          <header className="plan-group-heading">
            <div>
              <h3 id={`plan-group-${group.key}`}>{group.label}</h3>
              <p>{group.description}</p>
            </div>
            <span>{group.tasks.length}</span>
          </header>
        )
      ) : null}
      <div className="plan-list">
        <div className="plan-list-columns" aria-hidden="true">
          <span>Plan</span>
          <span>Repository</span>
          <span>Status</span>
          <span>Updated</span>
          <span>Progress</span>
        </div>
        {group.tasks.map((task) => (
          <PlanRow
            key={taskKey(task)}
            task={task}
            active={selectedTask ? taskKey(task) === taskKey(selectedTask) : false}
            mirrorGroup={mirrorGroups.get(taskKey(task))}
            changed={changedKeys.has(taskKey(task))}
            onSelect={() => onSelect(task)}
            onRun={onRun}
          />
        ))}
      </div>
    </section>
  );
}

function PlanRow({
  task,
  active,
  mirrorGroup,
  changed,
  onSelect,
  onRun
}: {
  task: PlanTask;
  active: boolean;
  mirrorGroup: MirrorGroup | undefined;
  changed: boolean;
  onSelect: () => void;
  onRun: (task: PlanTask) => void;
}) {
  return (
    <div className={active ? 'plan-row plan-row-active' : 'plan-row'}>
      <button
        className="plan-row-surface"
        type="button"
        onClick={onSelect}
        aria-current={active ? 'true' : undefined}
        data-task-key={taskKey(task)}
      >
        <div className="plan-row-content">
          <strong><ChangedDot changed={changed} />{task.title}</strong>
          <p>{rowInstruction(task)}</p>
        </div>
        <div className="plan-row-repo">
          <span className="plan-repo-chip">{task.repo}</span>
          <MirrorBadge group={mirrorGroup} />
        </div>
        <div className="plan-row-signal">
          <SignalBadge signal={planSignal(task)} />
        </div>
        <div className="plan-row-updated">
          <Clock3 size={14} aria-hidden="true" />
          <span>{relativeModified(task)}</span>
        </div>
        <div className="plan-row-progress">
          <span>{progressLabel(task)}</span>
          <ProgressBar task={task} />
        </div>
      </button>
      <QuickRunButton task={task} onRun={onRun} />
    </div>
  );
}

function SignalBadge({ signal }: { signal: ReturnType<typeof planSignal> }) {
  return <span className={`signal-badge signal-${signal.tone}`}>{signal.label}</span>;
}

function ProgressBar({ task }: { task: PlanTask }) {
  const value = task.progress_percent ?? 0;
  return (
    <span className={task.progress_percent === null ? 'progress progress-empty' : 'progress'} aria-label={progressLabel(task)}>
      <i style={{ width: `${value}%` }} />
    </span>
  );
}

function PlanInspector({
  task,
  mirrorGroup,
  copyFeedback,
  actionMessage,
  isAgentBusy,
  onClose,
  onCopy,
  onCopyAgentPrompt,
  onCopyPath,
  onRun
}: {
  task: PlanTask;
  mirrorGroup: MirrorGroup | undefined;
  copyFeedback: CopyFeedback | null;
  actionMessage: string;
  isAgentBusy: boolean;
  onClose: () => void;
  onCopy: (task: PlanTask) => void;
  onCopyAgentPrompt: (task: PlanTask) => void;
  onCopyPath: (task: PlanTask) => void;
  onRun: (task: PlanTask) => void;
}) {
  const mirrors = mirrorGroup?.mirrors ?? [task];
  const [targetKey, setTargetKey] = useState(taskKey(task));

  useEffect(() => {
    setTargetKey(taskKey(task));
  }, [task.absolutePath, task.repo]);

  const target = mirrors.find((mirror) => taskKey(mirror) === targetKey) ?? task;
  const steps = task.open_steps.slice(0, 8);
  const isBacklog = task.bucket === 'backlog';

  return (
    <div className="inspector-content">
      <div className="inspector-toolbar">
        <span className="inspector-repo">{task.repo} / {bucketLabel(task.bucket)}</span>
        <div>
          <button className="inspector-copy" type="button" onClick={() => onCopy(target)} aria-label="Copy prompt">
            <Copy size={17} aria-hidden="true" />
          </button>
          <button className="inspector-close" type="button" onClick={onClose} aria-label="Close details">
            <X size={19} aria-hidden="true" />
          </button>
        </div>
      </div>

      <div className="inspector-scroll">
        <header className="inspector-header">
          <SignalBadge signal={planSignal(task)} />
          <h3>{task.title}</h3>
          <p className="inspector-decision">{planDecision(task)}</p>
          <dl className="inspector-summary">
            <div>
              <dt><CalendarDays size={15} aria-hidden="true" />Created</dt>
              <dd>{formatDateValue(task.created)}</dd>
            </div>
            <div>
              <dt><Clock3 size={15} aria-hidden="true" />Updated</dt>
              <dd>{formatDateValue(task.git_last_modified)}</dd>
            </div>
            <div>
              <dt><FileText size={15} aria-hidden="true" />Progress</dt>
              <dd>{progressLabel(task)}</dd>
            </div>
          </dl>
        </header>

        <section className="inspector-section next-steps" aria-labelledby="next-steps-title">
          <div className="inspector-section-heading">
            <span className="utility-label" id="next-steps-title">Next steps</span>
            {task.open_steps.length > steps.length ? <small>+{task.open_steps.length - steps.length}</small> : null}
          </div>
          {steps.length > 0 ? (
            <ol>
              {steps.map((step, index) => (
                <li key={`${step}-${index}`}>
                  <span className="readonly-checkbox" aria-hidden="true" />
                  <p>{step}</p>
                </li>
              ))}
            </ol>
          ) : (
            <div className="inspector-note">
              <CheckCircle2 size={18} aria-hidden="true" />
              <p>{task.checkbox_total > 0 ? 'No open checkboxes remain.' : 'The plan has no actionable checkboxes.'}</p>
            </div>
          )}
        </section>

        <section className="inspector-section metadata-panel" aria-labelledby="metadata-title">
          <span className="utility-label" id="metadata-title">Context</span>
          <p className="inspector-scope">{task.scope === 'metadata_missing' ? 'Scope is missing.' : task.scope}</p>
          <dl>
            <div><dt>Status</dt><dd>{task.status}</dd></div>
            <div><dt>Lifecycle</dt><dd>{bucketLabel(task.bucket)}</dd></div>
            <div className="metadata-wide"><dt>Path</dt><dd>{task.path}</dd></div>
          </dl>
          {task.stale_reasons.length > 0 ? (
            <div className="reason-list">
              {task.stale_reasons.map((reason) => <span key={reason}>{humanizeReason(reason)}</span>)}
            </div>
          ) : null}
        </section>

        <section className="inspector-section route-panel" aria-labelledby="route-title">
          <div className="inspector-section-heading">
            <span className="utility-label" id="route-title">Checks</span>
            <small>{checkpointSummary(task)}</small>
          </div>
          <ExecutionRoute task={task} />
        </section>
      </div>

      <footer className="inspector-footer">
        {mirrors.length > 1 ? (
          <div className="mirror-picker">
            <span className="utility-label">Run in repository</span>
            <div>
              {mirrors.map((mirror) => (
                <button
                  className={taskKey(mirror) === targetKey ? 'mirror-option mirror-option-active' : 'mirror-option'}
                  type="button"
                  aria-pressed={taskKey(mirror) === targetKey}
                  onClick={() => setTargetKey(taskKey(mirror))}
                  key={taskKey(mirror)}
                >
                  {mirror.repo}
                </button>
              ))}
            </div>
          </div>
        ) : null}
        <div className="inspector-actions">
          <button
            className="primary-action"
            type="button"
            onClick={() => onRun(target)}
            disabled={isAgentBusy || !isMarkdownPlan(task)}
            title={isMarkdownPlan(task)
              ? `${primaryActionLabel(task)} in ${target.repo}`
              : 'Available only for Markdown plans'}
          >
            <PlayCircle size={17} aria-hidden="true" />
            {isAgentBusy ? 'Copying' : primaryActionLabel(task)}
          </button>
          <button className="secondary-action" type="button" onClick={() => onCopy(target)}>
            <Copy size={17} aria-hidden="true" />
            {copyLabel(copyFeedback, 'action', 'Action prompt')}
          </button>
          <button
            className="secondary-action"
            type="button"
            onClick={() => onCopyAgentPrompt(target)}
            title="Provider-neutral prompt for any coding agent"
          >
            <Copy size={17} aria-hidden="true" />
            {copyLabel(copyFeedback, 'agent', 'Agent prompt')}
          </button>
          <button
            className="secondary-action"
            type="button"
            onClick={() => onCopyPath(target)}
            title={target.sourceFile ?? target.absolutePath}
          >
            <Link2 size={17} aria-hidden="true" />
            {copyLabel(copyFeedback, 'path', 'Plan path')}
          </button>
        </div>
        {actionMessage ? <p className="action-message" role="status">{actionMessage}</p> : null}
        <p className="read-only-note">
          {isBacklog
            ? 'Run the copied prompt in an agent; the dashboard will detect the active plan.'
            : 'Read-only index: run the copied prompt in your chosen coding agent.'}
        </p>
      </footer>
    </div>
  );
}

function primaryActionLabel(task: PlanTask): string {
  if (task.bucket === 'backlog') return 'Copy activation prompt';
  if (isReadyToClose(task)) return 'Copy review prompt';
  return 'Copy next-step prompt';
}

function ExecutionRoute({ task }: { task: PlanTask }) {
  return (
    <div className="execution-route">
      {checkpointStates(task).map((checkpoint, index) => (
        <div className={`route-step route-${checkpoint.state}`} key={checkpoint.key}>
          <span className="route-marker" aria-hidden="true">
            {checkpoint.state === 'done'
              ? <Check size={14} />
              : checkpoint.state === 'issue'
                ? <AlertTriangle size={14} />
                : index + 1}
          </span>
          <div>
            <strong>{checkpoint.label}</strong>
            <p>{checkpoint.detail}</p>
          </div>
        </div>
      ))}
    </div>
  );
}

function LoadingState() {
  return (
    <div className="loading-state" aria-live="polite">
      <span className="loading-line" />
      <span className="loading-line" />
      <span className="loading-line" />
      <p>Building the plan index…</p>
    </div>
  );
}

function EmptyState({
  view,
  search,
  hasFlags,
  onClearSearch,
  onClearFlags
}: {
  view: WorkspaceView;
  search: string;
  hasFlags: boolean;
  onClearSearch: () => void;
  onClearFlags: () => void;
}) {
  const title = search ? 'No results' : hasFlags ? 'No plans match the filters' : emptyTitle(view);
  const description = search
    ? 'Change the query or return to the full list.'
    : hasFlags
      ? 'This view has no plans with the selected quality signals.'
      : emptyDescription(view);

  return (
    <div className="empty-state">
      <CheckCircle2 size={28} aria-hidden="true" />
      <h3>{title}</h3>
      <p>{description}</p>
      {search ? <button type="button" onClick={onClearSearch}>Clear search</button> : null}
      {!search && hasFlags ? <button type="button" onClick={onClearFlags}>Reset filters</button> : null}
    </div>
  );
}

function PlanHandoffReceipt({
  handoff,
  isRescanning,
  onDismiss,
  onOpen,
  onRescan
}: {
  handoff: PlanHandoff;
  isRescanning: boolean;
  onDismiss: () => void;
  onOpen: () => void;
  onRescan: () => void | Promise<void>;
}) {
  const isFound = handoff.state === 'found';
  const targetLabel = handoff.targetBucket === 'backlog' ? 'Backlog' : 'Active';
  const eyebrow = isFound
    ? handoff.kind === 'create' ? 'Plan found' : 'Plan activated'
    : handoff.kind === 'create' ? 'Prompt copied' : 'Waiting for activation';
  const detail = isFound
    ? handoff.kind === 'create'
      ? `The idea is now visible in ${targetLabel}.`
      : 'The active plan is visible in the index and ready to continue.'
    : handoff.kind === 'create'
      ? `Run the copied prompt; the watcher will add the saved plan to ${targetLabel}.`
      : 'Run the copied prompt; the dashboard will detect the move to active.';

  return (
    <section
      className={isFound ? 'handoff-receipt handoff-receipt-found' : 'handoff-receipt'}
      aria-live="polite"
      aria-label="Plan handoff status"
    >
      <span className="handoff-receipt-icon" aria-hidden="true">
        {isFound ? <CheckCircle2 size={18} /> : <Clock3 size={18} />}
      </span>
      <div className="handoff-receipt-copy">
        <span>{eyebrow}</span>
        <strong>{handoff.title}</strong>
        <p>{detail}</p>
      </div>
      <div className="handoff-receipt-actions">
        {isFound ? (
          <button className="handoff-primary-action" type="button" onClick={onOpen}>
            Open plan
            <ArrowRight size={15} aria-hidden="true" />
          </button>
        ) : (
          <button type="button" onClick={onRescan} disabled={isRescanning}>
            <RefreshCw className={isRescanning ? 'spin' : ''} size={15} aria-hidden="true" />
            {isRescanning ? 'Checking' : 'Check index'}
          </button>
        )}
        <button className="handoff-dismiss" type="button" onClick={onDismiss} aria-label="Dismiss handoff status">
          <X size={17} aria-hidden="true" />
        </button>
      </div>
    </section>
  );
}

function CreatePlanDialog({
  repositories,
  defaultRepo,
  defaultBucket,
  onHandoff,
  onClose
}: {
  repositories: RepoSummary[];
  defaultRepo: RepoSelection;
  defaultBucket: CreatePlanBucket;
  onHandoff: (handoff: CreatePlanHandoff) => void;
  onClose: () => void;
}) {
  const initialRepo = defaultRepo !== 'all'
    ? repositories.find((repository) => repository.name === defaultRepo)?.path
    : repositories[0]?.path;
  const [projectPath, setProjectPath] = useState(initialRepo ?? '');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [bucket, setBucket] = useState<CreatePlanBucket>(defaultBucket);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const titleRef = useRef<HTMLInputElement>(null);
  const isValid = Boolean(projectPath && title.trim());

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!isValid) return;
    setIsSubmitting(true);
    setErrorMessage('');

    try {
      await navigator.clipboard.writeText(buildCreatePlanPrompt({
        projectPath,
        title: title.trim(),
        description: description.trim(),
        bucket
      }));
      onHandoff({
        projectPath,
        title: title.trim(),
        bucket
      });
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'copy_failed');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="dialog-backdrop create-plan-backdrop" role="presentation" onMouseDown={onClose}>
      <form
        className="create-plan-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-plan-title"
        onSubmit={submit}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="dialog-heading">
          <div>
            <p className="utility-label">Backlog by default</p>
            <h3 id="create-plan-title">New idea</h3>
          </div>
          <button type="button" onClick={onClose} aria-label="Close"><X size={19} aria-hidden="true" /></button>
        </div>

        <div className="create-plan-form">
          <label>
            <span>Repository</span>
            <select value={projectPath} onChange={(event) => setProjectPath(event.target.value)}>
              {repositories.map((repository) => (
                <option value={repository.path} key={repository.path}>{repository.name}</option>
              ))}
            </select>
          </label>

          <label>
            <span>Title</span>
            <input
              ref={titleRef}
              value={title}
              maxLength={160}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="For example: Release calendar"
            />
          </label>

          <label>
            <span>Notes <small>optional</small></span>
            <textarea
              value={description}
              maxLength={4000}
              rows={5}
              onChange={(event) => setDescription(event.target.value)}
              placeholder="Context, constraints, or desired outcome"
            />
          </label>

          <fieldset>
            <legend>Mode</legend>
            <div className="segmented-choice">
              {([
                ['backlog', 'Save idea'],
                ['active', 'Start now']
              ] as Array<[CreatePlanBucket, string]>).map(([value, label]) => (
                <button
                  className={bucket === value ? 'choice-pill choice-pill-active' : 'choice-pill'}
                  type="button"
                  aria-pressed={bucket === value}
                  onClick={() => setBucket(value)}
                  key={value}
                >
                  {label}
                </button>
              ))}
            </div>
            <p className="create-plan-mode-note">
              {bucket === 'backlog'
                ? 'Copy a prompt for a backlog plan. The dashboard will show it after the agent saves the file.'
                : 'Copy a prompt for an active plan with an actionable first step.'}
            </p>
          </fieldset>

          <div className="create-plan-hint">
            <Lightbulb size={17} aria-hidden="true" />
            <p>The dashboard stays read-only. Your coding agent creates the file; the watcher adds it to the index.</p>
          </div>

          {errorMessage ? <p className="form-message form-message-error" role="alert">{errorMessage}</p> : null}
        </div>

        <footer className="create-plan-footer">
          <button className="secondary-action" type="button" onClick={onClose}>Cancel</button>
          <button className="create-plan-button" type="submit" disabled={!isValid || isSubmitting}>
            <PlayCircle size={17} aria-hidden="true" />
            {isSubmitting
              ? 'Copying prompt'
              : bucket === 'backlog'
                ? 'Copy idea prompt'
                : 'Copy active-plan prompt'}
          </button>
        </footer>
      </form>
    </div>
  );
}

function NavigatorDialog({
  tasks,
  repositories,
  viewCounts,
  repoCounts,
  selectedView,
  selectedRepo,
  allReposCount,
  onView,
  onRepo,
  onTask,
  onClose
}: {
  tasks: PlanTask[];
  repositories: RepoSummary[];
  viewCounts: Record<WorkspaceView, number>;
  repoCounts: Map<string, number>;
  selectedView: WorkspaceView;
  selectedRepo: RepoSelection;
  allReposCount: number;
  onView: (view: WorkspaceView) => void;
  onRepo: (repo: RepoSelection) => void;
  onTask: (task: PlanTask) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const normalizedQuery = query.trim().toLowerCase();

  const planMatches = useMemo(
    () => (normalizedQuery ? searchPlans(tasks, normalizedQuery) : []),
    [normalizedQuery, tasks]
  );
  const views = VIEW_DEFINITIONS.filter((item) =>
    `${item.label} ${item.description}`.toLowerCase().includes(normalizedQuery)
  );
  const repos = repositories.filter((repo) => repo.name.toLowerCase().includes(normalizedQuery));

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    setActiveIndex(0);
  }, [normalizedQuery]);

  function handleKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (planMatches.length === 0) return;

    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const direction = event.key === 'ArrowDown' ? 1 : -1;
      setActiveIndex((current) => (
        (current + direction + planMatches.length) % planMatches.length
      ));
      return;
    }

    if (event.key === 'Enter') {
      event.preventDefault();
      onTask(planMatches[activeIndex]);
    }
  }

  return (
    <div className="dialog-backdrop navigator-backdrop" role="presentation" onMouseDown={onClose}>
      <section
        className="navigator-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="navigator-title"
        onMouseDown={(event) => event.stopPropagation()}
        onKeyDown={handleKeyDown}
      >
        <div className="navigator-search">
          <Search size={18} aria-hidden="true" />
          <input
            ref={inputRef}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Find a plan, view, or repository"
            aria-label="Search plans and navigation"
          />
          <kbd>Esc</kbd>
        </div>

        <div className="navigator-results">
          {planMatches.length > 0 ? (
            <div className="navigator-section">
              <p className="utility-label" id="navigator-title">Plans</p>
              {planMatches.map((task, index) => (
                <button
                  className={index === activeIndex ? 'navigator-item navigator-item-active' : 'navigator-item'}
                  type="button"
                  key={taskKey(task)}
                  onMouseEnter={() => setActiveIndex(index)}
                  onClick={() => onTask(task)}
                >
                  <span>
                    <strong>{task.title}</strong>
                    <small>{task.repo} · {bucketLabel(task.bucket)}{task.next_open_step ? ` · ${task.next_open_step}` : ''}</small>
                  </span>
                  <em>{task.progress_percent === null ? '—' : `${task.progress_percent}%`}</em>
                </button>
              ))}
            </div>
          ) : null}

          {views.length > 0 ? (
            <div className="navigator-section">
              <p className="utility-label" id={planMatches.length > 0 ? undefined : 'navigator-title'}>Views</p>
              {views.map((item) => (
                <button
                  className={selectedView === item.key ? 'navigator-item navigator-item-active' : 'navigator-item'}
                  type="button"
                  key={item.key}
                  onClick={() => onView(item.key)}
                >
                  <span><strong>{item.label}</strong><small>{item.description}</small></span>
                  <em>{viewCounts[item.key]}</em>
                </button>
              ))}
            </div>
          ) : null}

          {repos.length > 0 || !normalizedQuery ? (
            <div className="navigator-section">
              <p className="utility-label">Repositories</p>
              {!normalizedQuery || 'all repositories'.includes(normalizedQuery) ? (
                <button
                  className={selectedRepo === 'all' ? 'navigator-item navigator-item-active' : 'navigator-item'}
                  type="button"
                  onClick={() => onRepo('all')}
                >
                  <span><strong>All repositories</strong><small>Full index scope</small></span>
                  <em>{allReposCount}</em>
                </button>
              ) : null}
              {repos.map((repo) => (
                <button
                  className={selectedRepo === repo.name ? 'navigator-item navigator-item-active' : 'navigator-item'}
                  type="button"
                  key={repo.name}
                  onClick={() => onRepo(repo.name)}
                >
                  <span><strong>{repo.name}</strong><small>{repo.counts.total} indexed</small></span>
                  <em>{repoCounts.get(repo.name) ?? 0}</em>
                </button>
              ))}
            </div>
          ) : null}

          {planMatches.length === 0 && views.length === 0 && repos.length === 0 ? (
            <p className="navigator-empty">No results</p>
          ) : null}
        </div>
      </section>
    </div>
  );
}

/** Активные планы важнее backlog, backlog важнее архива — архив редко ищут первым. */
function searchPlans(tasks: PlanTask[], query: string): PlanTask[] {
  const bucketRank: Record<PlanTask['bucket'], number> = { active: 0, backlog: 1, completed: 2 };

  return tasks
    .filter((task) => (
      [task.title, task.repo, task.path, task.scope, task.next_open_step ?? '']
        .join(' ')
        .toLowerCase()
        .includes(query)
    ))
    .sort((left, right) => (
      bucketRank[left.bucket] - bucketRank[right.bucket]
      || Number(right.title.toLowerCase().startsWith(query)) - Number(left.title.toLowerCase().startsWith(query))
      || left.title.localeCompare(right.title, 'ru')
    ))
    .slice(0, 8);
}

function ShortcutsDialog({ onClose }: { onClose: () => void }) {
  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="shortcuts-dialog" role="dialog" aria-modal="true" aria-labelledby="shortcuts-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-heading">
          <div>
            <p className="utility-label">Keyboard-first</p>
            <h3 id="shortcuts-title">Keyboard shortcuts</h3>
          </div>
          <button type="button" onClick={onClose} aria-label="Close"><X size={19} /></button>
        </div>
        <dl className="shortcut-list">
          <div><dt><kbd>⌘</kbd><kbd>K</kbd></dt><dd>Open navigator</dd></div>
          <div><dt><kbd>N</kbd></dt><dd>Save a new idea</dd></div>
          <div><dt><kbd>/</kbd></dt><dd>Focus search</dd></div>
          <div><dt><kbd>J</kbd><kbd>K</kbd></dt><dd>Next / previous plan</dd></div>
          <div><dt><kbd>Enter</kbd></dt><dd>Open selected plan details</dd></div>
          <div><dt><kbd>Esc</kbd></dt><dd>Close overlay or clear search</dd></div>
          <div><dt><kbd>?</kbd></dt><dd>Show this help</dd></div>
        </dl>
      </section>
    </div>
  );
}

function countViews(tasks: PlanTask[]): Record<WorkspaceView, number> {
  return {
    focus: tasks.filter((task) => matchesView(task, 'focus')).length,
    active: tasks.filter((task) => task.bucket === 'active').length,
    backlog: tasks.filter((task) => task.bucket === 'backlog').length,
    completed: tasks.filter((task) => task.bucket === 'completed').length
  };
}

function countQualityFlags(tasks: PlanTask[]): Record<QualityFlag, number> {
  return {
    stale: tasks.filter((task) => matchesQualityFlag(task, 'stale')).length,
    metadata: tasks.filter((task) => matchesQualityFlag(task, 'metadata')).length,
    validation: tasks.filter((task) => matchesQualityFlag(task, 'validation')).length,
    completion: tasks.filter((task) => matchesQualityFlag(task, 'completion')).length
  };
}

function matchesView(task: PlanTask, view: WorkspaceView): boolean {
  if (view === 'focus') return task.bucket === 'active';
  return task.bucket === view;
}

function matchesQualityFlag(task: PlanTask, flag: QualityFlag): boolean {
  if (flag === 'stale') return task.is_stale;
  if (flag === 'metadata') return task.missing_metadata.length > 0;
  if (flag === 'validation') return task.missing_validation_sections.length > 0;
  return task.completion_health === 'missing_completion_notes';
}

function buildPlanGroups(tasks: PlanTask[], view: WorkspaceView): PlanGroup[] {
  // Архив без группировки — это 149 строк подряд, в которых ничего не найти.
  if (view === 'completed') {
    return buildArchiveGroups(tasks);
  }

  if (view !== 'focus') {
    return [{ key: 'all', label: '', description: '', tasks, startIndex: 0 }];
  }

  const definitions: Array<Omit<PlanGroup, 'tasks' | 'startIndex'>> = [
    {
      key: 'ready',
      label: 'Ready to close',
      description: 'Work is complete; verify the result and record completion'
    },
    {
      key: 'attention',
      label: 'Needs a decision',
      description: 'Blocked, stale, missing context, or missing a next step'
    },
    {
      key: 'continue',
      label: 'Continue',
      description: 'Has a clear next step and no blocking signals'
    }
  ];

  let startIndex = 0;
  return definitions.flatMap((definition) => {
    const groupedTasks = tasks.filter((task) => focusGroup(task) === definition.key);
    if (groupedTasks.length === 0) return [];
    const group: PlanGroup = { ...definition, tasks: groupedTasks, startIndex };
    startIndex += groupedTasks.length;
    return [group];
  });
}

function buildArchiveGroups(tasks: PlanTask[]): PlanGroup[] {
  const months = new Map<string, PlanTask[]>();

  for (const task of tasks) {
    const date = planDate(task);
    const key = date ? `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}` : 'unknown';
    const bucket = months.get(key);
    if (bucket) {
      bucket.push(task);
    } else {
      months.set(key, [task]);
    }
  }

  let startIndex = 0;
  return [...months.entries()]
    .sort(([left], [right]) => right.localeCompare(left))
    .map(([key, monthTasks]) => {
      const group: PlanGroup = {
        key: `month-${key}`,
        label: key === 'unknown' ? 'No date' : formatMonth(key),
        description: `${monthTasks.length} ${pluralizePlans(monthTasks.length)}`,
        tasks: monthTasks,
        startIndex
      };
      startIndex += monthTasks.length;
      return group;
    });
}

function formatMonth(key: string): string {
  const [year, month] = key.split('-').map(Number);
  return new Intl.DateTimeFormat('ru-RU', { month: 'long', year: 'numeric' })
    .format(new Date(year, month - 1, 1));
}

function buildBoardColumns(tasks: PlanTask[]): BoardColumn[] {
  const definitions: Array<Omit<BoardColumn, 'tasks'>> = [
    {
      key: 'todo',
      label: 'To start',
      description: 'Not started or waiting for priority'
    },
    {
      key: 'progress',
      label: 'In progress',
      description: 'Has completed steps and a next action'
    },
    {
      key: 'review',
      label: 'Needs a decision',
      description: 'Needs context or an unblock decision'
    },
    {
      key: 'done',
      label: 'Done',
      description: 'Ready for review or already closed'
    }
  ];

  return definitions.map((definition) => ({
    ...definition,
    tasks: tasks.filter((task) => boardStage(task) === definition.key)
  }));
}

function boardStage(task: PlanTask): BoardTone {
  if (task.bucket === 'completed' || isReadyToClose(task)) return 'done';
  if (
    task.missing_metadata.length > 0
    || ['blocked', 'paused', 'deferred'].includes(task.status.toLowerCase())
    || (task.bucket === 'active' && task.checkbox_total > 0 && task.open_steps.length === 0)
  ) {
    return 'review';
  }
  if (task.bucket === 'backlog' || task.progress_percent === null || task.progress_percent === 0) return 'todo';
  return 'progress';
}

function planDate(task: PlanTask): Date | null {
  const raw = task.git_last_modified !== 'metadata_missing'
    ? task.git_last_modified
    : task.timeline_date;
  const timestamp = Date.parse(raw);
  return Number.isNaN(timestamp) ? null : new Date(timestamp);
}

/** Понедельник недели, в которую попадает дата. Группирующий ключ таймлайна. */
function weekStart(date: Date): Date {
  const mondayOffset = (date.getDay() + 6) % 7;
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() - mondayOffset);
}

function buildTimelineWeeks(tasks: PlanTask[]): TimelineWeek[] {
  const weeks = new Map<number, PlanTask[]>();
  const undated: PlanTask[] = [];

  for (const task of tasks) {
    const date = planDate(task);
    if (!date) {
      undated.push(task);
      continue;
    }
    const key = weekStart(date).getTime();
    const bucket = weeks.get(key);
    if (bucket) {
      bucket.push(task);
    } else {
      weeks.set(key, [task]);
    }
  }

  const ordered: TimelineWeek[] = [...weeks.entries()]
    .sort(([left], [right]) => right - left)
    .map(([key, weekTasks]) => ({
      key: String(key),
      label: weekLabel(new Date(key)),
      hint: weekHint(new Date(key)),
      tasks: weekTasks
    }));

  if (undated.length > 0) {
    ordered.push({
      key: 'undated',
      label: 'No modified date',
      hint: 'Git has no modification date for this file',
      tasks: undated
    });
  }

  return ordered;
}

function weekLabel(start: Date): string {
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6);
  const dayMonth = new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'short' });
  return `${dayMonth.format(start)} — ${dayMonth.format(end)} ${end.getFullYear()}`;
}

function weekHint(start: Date): string {
  const currentWeek = weekStart(new Date()).getTime();
  const weeksAgo = Math.round((currentWeek - start.getTime()) / (7 * 24 * 60 * 60 * 1000));
  if (weeksAgo <= 0) return 'This week';
  if (weeksAgo === 1) return 'Last week';
  if (weeksAgo < 5) return `${weeksAgo} weeks ago`;
  const monthsAgo = Math.round(weeksAgo / 4.35);
  return monthsAgo <= 1 ? 'One month ago' : `${monthsAgo} months ago`;
}

function focusGroup(task: PlanTask): FocusGroupKey {
  if (isReadyToClose(task)) return 'ready';
  if (needsAttention(task)) return 'attention';
  return 'continue';
}

function comparePlans(left: PlanTask, right: PlanTask, sortMode: SortMode): number {
  if (sortMode === 'title') return left.title.localeCompare(right.title, 'ru');
  if (sortMode === 'progress') {
    return (right.progress_percent ?? -1) - (left.progress_percent ?? -1) || compareDates(right, left);
  }
  if (sortMode === 'updated') return compareDates(right, left) || left.title.localeCompare(right.title, 'ru');

  return priorityScore(right) - priorityScore(left) || compareDates(right, left);
}

function priorityScore(task: PlanTask): number {
  let score = 0;
  if (isReadyToClose(task)) score += 120;
  if (task.missing_metadata.length > 0) score += 100;
  if (['blocked', 'paused', 'deferred'].includes(task.status.toLowerCase())) score += 90;
  if (task.is_stale) score += 70;
  if (task.bucket === 'active' && task.open_steps.length === 0) score += 50;
  score += task.progress_percent ?? 0;
  return score;
}

function compareDates(left: PlanTask, right: PlanTask): number {
  return dateScore(left) - dateScore(right);
}

function dateScore(task: PlanTask): number {
  const value = task.git_last_modified !== 'metadata_missing' ? task.git_last_modified : task.timeline_date;
  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function needsAttention(task: PlanTask): boolean {
  return task.is_stale
    || task.missing_metadata.length > 0
    || ['blocked', 'paused', 'deferred'].includes(task.status.toLowerCase())
    || (task.bucket === 'active' && task.open_steps.length === 0 && !isReadyToClose(task));
}

function isReadyToClose(task: PlanTask): boolean {
  return task.bucket === 'active' && task.progress_percent === 100;
}

function planSignal(task: PlanTask): { label: string; tone: 'default' | 'warning' | 'danger' | 'ready' } {
  const normalizedStatus = task.status.toLowerCase();
  if (['blocked', 'paused', 'deferred'].includes(normalizedStatus)) return { label: 'Blocked', tone: 'danger' };
  if (isReadyToClose(task)) return { label: 'Ready to close', tone: 'ready' };
  if (task.missing_metadata.length > 0) return { label: 'Missing context', tone: 'warning' };
  if (task.is_stale) return { label: 'Stale', tone: 'warning' };
  if (task.bucket === 'active' && task.open_steps.length === 0) return { label: 'No next step', tone: 'warning' };
  return { label: bucketLabel(task.bucket), tone: 'default' };
}

function checkpointStates(task: PlanTask) {
  const executionState: CheckpointState = task.progress_percent === 100
    ? 'done'
    : task.checkbox_total > 0
      ? 'current'
      : 'idle';
  const closureState: CheckpointState = task.bucket === 'completed'
    ? task.completion_health === 'ok' ? 'done' : 'issue'
    : isReadyToClose(task) ? 'current' : 'idle';

  return [
    {
      key: 'metadata',
      label: 'Metadata',
      state: task.missing_metadata.length === 0 ? 'done' as const : 'issue' as const,
      detail: task.missing_metadata.length === 0 ? 'Status, Created, and Scope are present' : `Missing: ${task.missing_metadata.join(', ')}`
    },
    {
      key: 'execution',
      label: 'Execution',
      state: executionState,
      detail: task.checkbox_total > 0 ? `${task.checkbox_done} of ${task.checkbox_total} steps complete` : 'No actionable checkboxes'
    },
    {
      key: 'validation',
      label: 'Validation',
      state: task.missing_validation_sections.length === 0 ? 'done' as const : 'issue' as const,
      detail: task.missing_validation_sections.length === 0 ? 'Commands and criteria are present' : `Missing: ${task.missing_validation_sections.join(', ')}`
    },
    {
      key: 'closure',
      label: 'Closure',
      state: closureState,
      detail: closureDetail(task)
    }
  ];
}

function closureDetail(task: PlanTask): string {
  if (task.bucket === 'completed') {
    return task.completion_health === 'ok' ? 'Completion Notes are present' : 'Completion Notes are missing';
  }
  if (isReadyToClose(task)) return 'All checkboxes are complete; review the result';
  return 'Completion review is not required yet';
}

function checkpointSummary(task: PlanTask): string {
  const issues = checkpointStates(task).filter((checkpoint) => checkpoint.state === 'issue').length;
  return issues === 0 ? 'All required checkpoints pass' : `${issues} checkpoint issues`;
}

function getViewDefinition(view: WorkspaceView): ViewDefinition {
  return VIEW_DEFINITIONS.find((item) => item.key === view) ?? WORK_VIEWS[0];
}

function taskKey(task: PlanTask): string {
  return `${task.repo}:${task.path}`;
}

function copyLabel(feedback: CopyFeedback | null, kind: CopyKind, idle: string): string {
  if (feedback?.kind !== kind) return idle;
  return feedback.ok ? 'Copied' : 'Error';
}

function bucketLabel(bucket: PlanTask['bucket']): string {
  if (bucket === 'active') return 'Active';
  if (bucket === 'backlog') return 'Backlog';
  return 'Completed';
}

function progressLabel(task: PlanTask): string {
  if (task.progress_percent === null) return 'No checkboxes';
  return `${task.progress_percent}% · ${task.checkbox_done}/${task.checkbox_total}`;
}

function planDecision(task: PlanTask): string {
  if (isReadyToClose(task)) return 'All actionable steps are complete. Review the result and close the plan.';
  if (['blocked', 'paused', 'deferred'].includes(task.status.toLowerCase())) {
    return 'Resolve the blocker or decide when to resume work.';
  }
  if (task.missing_metadata.length > 0) return 'Restore the plan context before continuing.';
  if (task.is_stale) return 'Decide whether to continue, defer, or close this stale plan.';
  if (task.next_open_step) return `Next step: ${task.next_open_step}`;
  return task.checkbox_total > 0
    ? 'No open steps remain; check whether the plan can be closed.'
    : 'The plan has no actionable checkboxes; define the next action.';
}

function rowInstruction(task: PlanTask): string {
  if (task.next_open_step) return task.next_open_step;
  if (isReadyToClose(task)) return 'Review the result and record plan completion.';
  if (task.missing_metadata.length > 0) return `Restore context: ${task.missing_metadata.join(', ')}.`;
  if (['blocked', 'paused', 'deferred'].includes(task.status.toLowerCase())) return 'Resolve the blocker or set a resume date.';
  if (task.scope !== 'metadata_missing') return task.scope;
  return 'Define the next actionable step.';
}

function relativeModified(task: PlanTask): string {
  const days = task.days_since_modified;
  if (days === null) return 'date unknown';
  if (days === 0) return 'today';
  if (days === 1) return 'yesterday';
  if (days < 7) return `${days} days ago`;
  if (days < 30) return `${Math.floor(days / 7)} weeks ago`;
  return `${Math.floor(days / 30)} months ago`;
}

function isMarkdownPlan(task: PlanTask): boolean {
  return (task.sourceFile ?? task.absolutePath).toLowerCase().endsWith('.md');
}

function pluralizePlans(value: number): string {
  const mod10 = value % 10;
  const mod100 = value % 100;
  return value === 1 ? 'plan' : 'plans';
}

function emptyTitle(view: WorkspaceView): string {
  if (view === 'focus') return 'Focus is clear';
  if (view === 'backlog') return 'Backlog is empty';
  return 'No plans in this view';
}

function emptyDescription(view: WorkspaceView): string {
  if (view === 'focus') return 'No active plans have a next step or attention signal.';
  if (view === 'backlog') return 'Use New idea to add work here.';
  return 'Choose another view or repository.';
}

function formatDateValue(value: MetadataValue): string {
  if (value === 'metadata_missing') return 'Not specified';
  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) return value;
  return new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(timestamp));
}

function formatTime(value: string): string {
  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp) || timestamp === 0) return '—';
  return new Intl.DateTimeFormat('ru-RU', { hour: '2-digit', minute: '2-digit' }).format(new Date(timestamp));
}

function reasonLabel(reason: string): string {
  if (reason === 'connected') return 'Index connected';
  if (reason === 'manual') return 'Rescanned';
  if (reason === 'watcher' || reason.startsWith('watch:')) return 'Changes detected';
  return 'Index updated';
}

function humanizeReason(reason: string): string {
  if (reason === 'status_missing') return 'Status is missing';
  if (reason === 'status_draft') return 'Plan is still a draft';
  const days = reason.match(/^git_older_than_(\d+)_days$/)?.[1];
  return days ? `No changes for more than ${days} days` : reason;
}

function readStoredString(key: string): string | null {
  if (typeof window === 'undefined') return null;
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStoredString(key: string, value: string | null) {
  if (typeof window === 'undefined') return;
  try {
    if (value) {
      window.localStorage.setItem(key, value);
    } else {
      window.localStorage.removeItem(key);
    }
  } catch {
    // Приватный режим браузера — состояние просто не переживёт перезагрузку.
  }
}

/**
 * Планы, тронутые после прошлого визита. Индикатор нужен только для незакрытой
 * работы: подсвечивать движение в архиве смысла нет.
 */
function collectChangedSince(tasks: PlanTask[], lastVisit: number): Set<string> {
  const changed = new Set<string>();
  if (!lastVisit) return changed;

  for (const task of tasks) {
    if (task.bucket === 'completed') continue;
    const timestamp = Date.parse(task.git_last_modified);
    if (!Number.isNaN(timestamp) && timestamp > lastVisit) {
      changed.add(taskKey(task));
    }
  }

  return changed;
}

function readPlanHandoff(): PlanHandoff | null {
  if (typeof window === 'undefined') return null;

  try {
    const raw = window.localStorage.getItem(PLAN_HANDOFF_STORAGE_KEY);
    if (!raw) return null;
    const value = JSON.parse(raw) as Partial<PlanHandoff>;
    const isValid =
      (value.kind === 'create' || value.kind === 'activate')
      && (value.state === 'waiting' || value.state === 'found')
      && (value.targetBucket === 'active' || value.targetBucket === 'backlog')
      && typeof value.repo === 'string'
      && typeof value.projectPath === 'string'
      && typeof value.title === 'string'
      && Array.isArray(value.knownTaskKeys)
      && value.knownTaskKeys.every((key) => typeof key === 'string')
      && typeof value.createdAt === 'number'
      && Date.now() - value.createdAt <= PLAN_HANDOFF_MAX_AGE_MS;

    return isValid ? value as PlanHandoff : null;
  } catch {
    return null;
  }
}

function persistPlanHandoff(handoff: PlanHandoff | null) {
  if (typeof window === 'undefined') return;
  try {
    if (handoff) {
      window.localStorage.setItem(PLAN_HANDOFF_STORAGE_KEY, JSON.stringify(handoff));
    } else {
      window.localStorage.removeItem(PLAN_HANDOFF_STORAGE_KEY);
    }
  } catch {
    // Если browser storage недоступен, handoff всё равно остаётся в React state.
  }
}

function readUrlState(): UrlState {
  if (typeof window === 'undefined') {
    return {
      repo: 'all',
      view: 'focus',
      flags: [],
      search: '',
      sort: 'priority',
      mode: 'board',
      mirrors: false,
      task: null
    };
  }

  const params = new URLSearchParams(window.location.search);
  const viewValue = params.get('view') ?? '';
  const sortValue = params.get('sort');
  const modeValue = params.get('mode');
  // `active` схлопнут в `focus`: они давали одно и то же множество планов.
  const requestedView = viewValue === 'active' ? 'focus' : viewValue;
  const legacyFlag = LEGACY_VIEW_FLAGS[viewValue];
  const flags = (params.get('flags') ?? '')
    .split(',')
    .filter((value): value is QualityFlag => QUALITY_FILTERS.some((filter) => filter.key === value));

  return {
    repo: params.get('repo') || 'all',
    // Старые quality-ссылки открываем в том lifecycle, где эти признаки действительно встречаются.
    view: VIEW_DEFINITIONS.some((item) => item.key === requestedView)
      ? requestedView as WorkspaceView
      : legacyFlag === 'completion'
        ? 'completed'
        : 'focus',
    flags: legacyFlag && !flags.includes(legacyFlag) ? [...flags, legacyFlag] : flags,
    search: params.get('q') ?? '',
    sort: ['priority', 'updated', 'progress', 'title'].includes(sortValue ?? '') ? sortValue as SortMode : 'priority',
    // `calendar` из старых ссылок ведёт на заменивший его таймлайн.
    mode: modeValue === 'calendar'
      ? 'timeline'
      : ['board', 'list', 'timeline'].includes(modeValue ?? '') ? modeValue as PresentationMode : 'board',
    mirrors: params.get('mirrors') === '1',
    task: params.get('task')
  };
}

function writeUrlState(state: UrlState) {
  if (typeof window === 'undefined') return;
  const params = new URLSearchParams();
  if (state.repo !== 'all') params.set('repo', state.repo);
  if (state.view !== 'focus') params.set('view', state.view);
  if (state.flags.length > 0) params.set('flags', state.flags.join(','));
  if (state.search) params.set('q', state.search);
  if (state.sort !== 'priority') params.set('sort', state.sort);
  if (state.mode !== 'board') params.set('mode', state.mode);
  if (state.mirrors) params.set('mirrors', '1');
  if (state.task) params.set('task', state.task);
  const query = params.toString();
  window.history.replaceState(null, '', `${window.location.pathname}${query ? `?${query}` : ''}`);
}
