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
    private var cancellable: AnyCancellable?
    private var refreshRequested = false

    init(accessStore: RepositoryAccessStore) {
        self.accessStore = accessStore
        cacheURL = accessStore.applicationSupportURL
            .appending(path: "snapshot.json", directoryHint: .notDirectory)
        let roots = accessStore.resolvedRepositories()
        if let cached = SnapshotCache.load(
            from: cacheURL,
            expectedRepositorySet: roots.map(\.registrationID)
        ) {
            snapshot = Snapshot(cached)
            connection = .connected
        }
        cancellable = accessStore.$repositories
            .dropFirst()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    func refresh() async {
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
                snapshot = .empty
                repositoryIssues = []
                connection = .unavailable("Add a repository root to start.")
                return
            }

            connection = .starting
            let validations = await Task.detached(priority: .userInitiated) {
                roots.map {
                    RepositoryValidator.validate(
                        rootURL: $0.url,
                        fallbackIdentity: $0.registrationID
                    )
                }
            }.value

            let uniqueValidations = Self.collapseConfirmedClones(validations)
            let cached = PlansSnapshot(
                repositorySet: roots.map(\.registrationID),
                validations: uniqueValidations
            )
            do {
                try SnapshotCache.save(cached, to: cacheURL)
            } catch {
                NSLog("Не удалось сохранить снимок PlansBar: %@", error.localizedDescription)
            }
            snapshot = Snapshot(cached)
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
            connection = .connected
        } while refreshRequested
    }

    private static func collapseConfirmedClones(
        _ validations: [RepositoryValidation]
    ) -> [RepositoryValidation] {
        var identities: Set<RepositoryIdentity> = []
        return validations.filter { validation in
            validation.identity.kind != .gitRemote || identities.insert(validation.identity).inserted
        }
    }

    func rescan() async {
        await refresh()
    }

    func copyPrompt(_ task: PlanTask) async -> String {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.portablePrompt, forType: .string)
        return "Prompt copied"
    }

    func copyPreparationPrompt(_ issue: RepositoryIssue) -> String {
        guard let prompt = issue.preparationPrompt else { return "Repository is not accessible" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        return "Preparation prompt copied"
    }
}
