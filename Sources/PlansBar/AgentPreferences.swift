import Foundation

enum AgentAdapter: String, CaseIterable, Identifiable {
    case askEveryTime = "ask_every_time"
    case codex
    case claude
    case copyOnly = "copy_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askEveryTime: return "Ask every time"
        case .codex: return "Codex CLI"
        case .claude: return "Claude Code CLI"
        case .copyOnly: return "Copy only"
        }
    }
}

@MainActor
final class AgentPreferences: ObservableObject {
    private static let preferredKey = "preferredAgent"

    @Published var preferred: AgentAdapter {
        didSet { UserDefaults.standard.set(preferred.rawValue, forKey: Self.preferredKey) }
    }

    init() {
        preferred = UserDefaults.standard.string(forKey: Self.preferredKey)
            .flatMap(AgentAdapter.init(rawValue:)) ?? .askEveryTime
    }
}
