import AppKit
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
    private static let executablePathsKey = "agentExecutablePaths"

    @Published var preferred: AgentAdapter {
        didSet { UserDefaults.standard.set(preferred.rawValue, forKey: Self.preferredKey) }
    }
    @Published private(set) var executablePaths: [String: String]

    init() {
        preferred = UserDefaults.standard.string(forKey: Self.preferredKey)
            .flatMap(AgentAdapter.init(rawValue:)) ?? .askEveryTime
        executablePaths = UserDefaults.standard.dictionary(forKey: Self.executablePathsKey) as? [String: String] ?? [:]
    }

    func executablePath(for adapter: AgentAdapter) -> String? {
        executablePaths[adapter.rawValue]
    }

    func chooseExecutable(for adapter: AgentAdapter) {
        guard adapter == .codex || adapter == .claude else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose \(adapter.title) Executable"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return }
        executablePaths[adapter.rawValue] = url.path
        UserDefaults.standard.set(executablePaths, forKey: Self.executablePathsKey)
    }

    func clearExecutable(for adapter: AgentAdapter) {
        executablePaths.removeValue(forKey: adapter.rawValue)
        UserDefaults.standard.set(executablePaths, forKey: Self.executablePathsKey)
    }
}
