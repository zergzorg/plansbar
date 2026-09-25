import AppKit
import Combine
import Foundation
import PlansCore

enum ConnectionState: Equatable {
    case starting
    case connected
    case unavailable(String)

    var label: String {
        switch self {
        case .starting: return "Starting index"
        case .connected: return "Index connected"
        case .unavailable: return "No repositories"
        }
    }
}

struct RepositoryIssue: Identifiable {
    let identity: RepositoryIdentity
    let name: String
    let path: String
    let state: RepositoryValidationState
    let missingPaths: [String]
    let invalidPlanCount: Int
    let preparationPrompt: String?

    var id: String { identity.rawValue }
}

@MainActor
final class IndexClient: ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty
    @Published private(set) var connection: ConnectionState = .unavailable(
        "Add a repository root to start."
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var repositoryIssues: [RepositoryIssue] = []

    private let accessStore: RepositoryAccessStore
    private let cacheURL: URL
    private let refreshEnabled: Bool
    private var cancellable: AnyCancellable?
    private var refreshRequested = false
    private let watcher = PlanWatcher()
    /// Git проверяется один раз за запуск: отсутствие исполняемого файла не
    /// должно приводить к повторным probe на каждом скане.
    private let git = GitCapability.probe()
    private var validations: [RepositoryValidation] = []

    init(accessStore: RepositoryAccessStore, initialSnapshot: Snapshot? = nil) {
        self.accessStore = accessStore
        refreshEnabled = initialSnapshot == nil
        cacheURL = accessStore.applicationSupportURL
            .appending(path: "snapshot.json", directoryHint: .notDirectory)
        if let initialSnapshot {
            snapshot = initialSnapshot
            connection = .connected
        } else {
            let roots = accessStore.resolvedRepositories()
            if let cached = SnapshotCache.load(
                from: cacheURL,
                expectedRepositorySet: roots.map(\.registrationID)
            ) {
                snapshot = Snapshot(cached)
                connection = .connected
            }
        }
        cancellable = accessStore.$repositories
            .dropFirst()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    func refresh() async {
        guard refreshEnabled else { return }
        if isRefreshing {
            refreshRequested = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshRequested = false
            let roots = accessStore.resolvedRepositories()
            guard !roots.isEmpty else {
                validations = []
                snapshot = .empty
                repositoryIssues = []
                connection = .unavailable("Add a repository root to start.")
                watcher.stop()
                return
            }

            connection = .starting
            // Сначала очередь, с которой работают каждый день: панель
            // становится живой до того, как разобран архив completed.
            let queueOnly = await validate(roots, buckets: [.active, .backlog])
            validations = queueOnly
            publish(repositorySet: roots.map(\.registrationID), persist: false)

            validations = await validate(roots, buckets: PlanBucket.allCases)
            publish(repositorySet: roots.map(\.registrationID), persist: true)
            connection = .connected
            startWatching(roots)
        } while refreshRequested
    }

    /// Пересканирует только те репозитории, из которых пришли события
    /// файловой системы; остальные остаются в снапшоте нетронутыми.
    private func refreshAffected(_ affectedRoots: Set<URL>) async {
        guard refreshEnabled, !isRefreshing else {
            refreshRequested = isRefreshing
            return
        }
        let roots = accessStore.resolvedRepositories()
        let affected = roots.filter { affectedRoots.contains($0.url.standardizedFileURL.resolvingSymlinksInPath()) }
        guard !affected.isEmpty else { return }

        isRefreshing = true
        let updated = await validate(affected, buckets: PlanBucket.allCases)
        var merged = validations
        for validation in updated {
            if let index = merged.firstIndex(where: { $0.identity == validation.identity }) {
                merged[index] = validation
            } else {
                merged.append(validation)
            }
        }
        validations = merged
        publish(repositorySet: roots.map(\.registrationID), persist: true)
        isRefreshing = false
        // Полный refresh, запрошенный во время частичного, иначе потеряется.
        if refreshRequested {
            await refresh()
        }
    }

    private func validate(
        _ roots: [ResolvedRepository],
        buckets: [PlanBucket]
    ) async -> [RepositoryValidation] {
        let git = git
        return await Task.detached(priority: .userInitiated) {
            roots.map {
                RepositoryValidator.validate(
                    rootURL: $0.url,
                    fallbackIdentity: $0.registrationID,
                    buckets: buckets,
                    git: git
                )
            }
        }.value
    }

    private func publish(repositorySet: [String], persist: Bool) {
        let uniqueValidations = Self.collapseConfirmedClones(validations)
        let plansSnapshot = PlansSnapshot(
            repositorySet: repositorySet,
            validations: uniqueValidations
        )
        if persist {
            do {
                try SnapshotCache.save(plansSnapshot, to: cacheURL)
            } catch {
                NSLog("Не удалось сохранить снимок PlansBar: %@", error.localizedDescription)
            }
        }
        snapshot = Snapshot(plansSnapshot)
        repositoryIssues = uniqueValidations.compactMap { validation in
            guard validation.state != .ready else { return nil }
            return RepositoryIssue(
                identity: validation.identity,
                name: validation.name,
                path: validation.rootURL.path,
                state: validation.state,
                missingPaths: validation.missingPaths,
                invalidPlanCount: validation.plans.filter { $0.parseState == .invalidPlan }.count,
                preparationPrompt: RepositoryPreparationPrompt.make(validation)
            )
        }
    }

    private func startWatching(_ roots: [ResolvedRepository]) {
        watcher.start(roots: roots.map(\.url)) { [weak self] affected in
            Task { @MainActor in
                await self?.refreshAffected(affected)
            }
        }
    }

    private static func collapseConfirmedClones(
        _ validations: [RepositoryValidation]
    ) -> [RepositoryValidation] {
        var identities: Set<RepositoryIdentity> = []
        return validations.filter { validation in
            validation.identity.kind != .gitRemote || identities.insert(validation.identity).inserted
        }
    }

    func perform(
        _ task: PlanTask,
        with adapter: AgentAdapter,
        executablePath: String?
    ) async -> String {
        await handOff(
            task.portablePrompt,
            repositoryPath: task.repoPath,
            adapter: adapter,
            executablePath: executablePath,
            copiedMessage: "Prompt copied"
        )
    }

    func copyPreparationPrompt(_ issue: RepositoryIssue) -> String {
        guard let prompt = issue.preparationPrompt else { return "Repository is not accessible" }
        copy(prompt)
        return "Preparation prompt copied"
    }

    func performPreparation(
        _ issue: RepositoryIssue,
        with adapter: AgentAdapter,
        executablePath: String?
    ) async -> String {
        guard let prompt = issue.preparationPrompt else { return "Repository is not accessible" }
        return await handOff(
            prompt,
            repositoryPath: issue.path,
            adapter: adapter,
            executablePath: executablePath,
            copiedMessage: "Preparation prompt copied"
        )
    }

    func performNewIdea(
        repository: RegisteredRepository,
        idea: String,
        with adapter: AgentAdapter,
        executablePath: String?
    ) async -> String {
        let prompt = AgentPrompt.makeNewIdea(NewIdeaPromptInput(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            idea: idea
        ))
        return await handOff(
            prompt,
            repositoryPath: repository.path,
            adapter: adapter,
            executablePath: executablePath,
            copiedMessage: "New idea prompt copied"
        )
    }

    private func handOff(
        _ prompt: String,
        repositoryPath: String,
        adapter: AgentAdapter,
        executablePath: String?,
        copiedMessage: String
    ) async -> String {
        if adapter == .copyOnly {
            copy(prompt)
            return copiedMessage
        }
        do {
            try await AgentLauncher.launch(
                adapter: adapter,
                repositoryPath: repositoryPath,
                prompt: prompt,
                executablePath: executablePath
            )
            return "Opened \(adapter.title) in Terminal"
        } catch {
            return error.localizedDescription
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
