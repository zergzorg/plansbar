import Foundation
import PlansCore

/// Подмножество `src/shared/types.ts`, которое нужно панели.
/// Разбор планов остаётся в TypeScript — здесь только чтение готового снапшота.
struct Snapshot: Codable {
    let generatedAt: String
    let repositories: [Repository]

    static let empty = Snapshot(generatedAt: "", repositories: [])
}

struct Repository: Codable, Identifiable {
    let name: String
    let path: String
    let tasks: [PlanTask]

    var id: String { name }
}

struct PlanTask: Codable, Identifiable {
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

    var id: String { "\(repo):\(path)" }

    enum CodingKeys: String, CodingKey {
        case repo
        case repoPath
        case path
        case absolutePath
        case sourceFile
        case bucket
        case title
        case status
        case checkboxTotal = "checkbox_total"
        case checkboxDone = "checkbox_done"
        case progressPercent = "progress_percent"
        case daysSinceModified = "days_since_modified"
        case nextOpenStep = "next_open_step"
        case missingMetadata = "missing_metadata"
        case isStale = "is_stale"
    }

    var planPath: String { sourceFile ?? absolutePath }
    var isMarkdown: Bool { planPath.lowercased().hasSuffix(".md") }
    var isActive: Bool { bucket == "active" }
    var isReadyToClose: Bool { isActive && progressPercent == 100 }

    var needsAttention: Bool {
        isStale
            || !missingMetadata.isEmpty
            || ["blocked", "paused", "deferred"].contains(status.lowercased())
            || (isActive && (nextOpenStep?.isEmpty ?? true) && !isReadyToClose)
    }

    var signal: PlanSignal {
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
        if bucket == "backlog" { return "Start plan" }
        if isReadyToClose { return "Review plan" }
        return "Copy prompt"
    }

    var portablePrompt: String {
        AgentPrompt.make(AgentPromptInput(
            planPath: planPath,
            repositoryName: repo,
            repositoryPath: repoPath,
            title: title,
            nextStep: nextOpenStep,
            completedSteps: checkboxDone,
            totalSteps: checkboxTotal
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
