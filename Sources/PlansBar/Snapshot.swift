import Foundation
import PlansCore

struct Snapshot {
    let generatedAt: String
    let repositories: [Repository]

    static let empty = Snapshot(generatedAt: "", repositories: [])

    init(generatedAt: String, repositories: [Repository]) {
        self.generatedAt = generatedAt
        self.repositories = repositories
    }

    init(_ snapshot: PlansSnapshot) {
        generatedAt = snapshot.generatedAt
        repositories = snapshot.validations.map(Repository.init)
    }
}

struct Repository: Identifiable {
    let identity: RepositoryIdentity
    let name: String
    let path: String
    let tasks: [PlanTask]

    var id: String { identity.rawValue }

    init(identity: RepositoryIdentity, name: String, path: String, tasks: [PlanTask]) {
        self.identity = identity
        self.name = name
        self.path = path
        self.tasks = tasks
    }

    init(_ validation: RepositoryValidation) {
        identity = validation.identity
        name = validation.name
        path = validation.rootURL.path
        tasks = validation.plans.map {
            PlanTask(
                $0,
                repositoryIdentity: validation.identity,
                repositoryName: validation.name,
                repositoryPath: validation.rootURL.path
            )
        }
    }
}

struct PlanTask: Identifiable {
    let repositoryIdentity: RepositoryIdentity
    let repo: String
    let repoPath: String
    let path: String
    let absolutePath: String
    let sourceFile: String?
    let bucket: String
    let title: String
    let status: String
    let checkboxTotal: Int
    let checkboxDone: Int
    let progressPercent: Int?
    let daysSinceModified: Int?
    let nextOpenStep: String?
    let missingMetadata: [String]
    let isStale: Bool
    let parseState: PlanParseState
    let lintErrors: [String]

    var id: String { "\(repositoryIdentity.rawValue):\(path)" }

    init(
        _ plan: PlanRecord,
        repositoryIdentity: RepositoryIdentity,
        repositoryName: String,
        repositoryPath: String
    ) {
        self.repositoryIdentity = repositoryIdentity
        repo = repositoryName
        repoPath = repositoryPath
        path = plan.relativePath
        absolutePath = plan.absolutePath
        sourceFile = nil
        bucket = plan.bucket.rawValue
        title = plan.title
        status = plan.status
        checkboxTotal = plan.checkboxTotal
        checkboxDone = plan.checkboxDone
        progressPercent = plan.progressPercent
        daysSinceModified = plan.daysSinceModified
        nextOpenStep = plan.nextOpenStep
        missingMetadata = plan.lintErrors
        isStale = plan.status == "draft" || (plan.daysSinceModified ?? 0) > 30
        parseState = plan.parseState
        lintErrors = plan.lintErrors
    }

    var planPath: String { sourceFile ?? absolutePath }
    var isMarkdown: Bool { planPath.lowercased().hasSuffix(".md") }
    var isActionable: Bool { isMarkdown && parseState == .parsed && bucket != "completed" }
    var isActive: Bool { bucket == "active" }
    var isReadyToClose: Bool { isActive && progressPercent == 100 }

    var needsAttention: Bool {
        isStale
            || parseState == .invalidPlan
            || !missingMetadata.isEmpty
            || ["blocked", "paused", "deferred"].contains(status.lowercased())
            || (isActive && (nextOpenStep?.isEmpty ?? true) && !isReadyToClose)
    }

    var signal: PlanSignal {
        if parseState == .invalidPlan { return .noContext }
        if ["blocked", "paused", "deferred"].contains(status.lowercased()) { return .blocked }
        if isReadyToClose { return .ready }
        if !missingMetadata.isEmpty { return .noContext }
        if isStale { return .stale }
        return .normal
    }

    var progressLabel: String {
        guard let percent = progressPercent else { return "no steps" }
        return "\(percent)% · \(checkboxDone)/\(checkboxTotal)"
    }

    var progressCountLabel: String {
        guard checkboxTotal > 0 else { return "no steps" }
        return "\(checkboxDone)/\(checkboxTotal)"
    }

    var modifiedLabel: String {
        guard let days = daysSinceModified else { return "date unknown" }
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<30: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }

    var actionTitle: String {
        if parseState == .invalidPlan { return "Needs preparation" }
        if bucket == "backlog" { return "Start plan" }
        if isReadyToClose { return "Review plan" }
        return "Continue plan"
    }

    var portablePrompt: String {
        AgentPrompt.make(AgentPromptInput(
            planPath: planPath,
            repositoryName: repo,
            repositoryPath: repoPath,
            title: title,
            nextStep: nextOpenStep,
            completedSteps: checkboxDone,
            totalSteps: checkboxTotal,
            intent: bucket == "backlog" ? .activatePlan : (isReadyToClose ? .closePlan : .continuePlan)
        ))
    }
}

enum PlanSignal {
    case normal, ready, stale, noContext, blocked

    var label: String {
        switch self {
        case .normal: return "in progress"
        case .ready: return "ready to close"
        case .stale: return "stale"
        case .noContext: return "missing context"
        case .blocked: return "blocked"
        }
    }
}
