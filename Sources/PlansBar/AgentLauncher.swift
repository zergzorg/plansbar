import AppKit
import Foundation
import PlansCore

enum AgentLaunchError: LocalizedError {
    case unsupportedAdapter
    case executableMissing(String)
    case gitUnavailable
    case repositoryChanged
    case gitCheckFailed
    case gitCheckTimedOut
    case terminalAutomationDenied(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAdapter:
            return "Choose Codex CLI or Claude Code CLI."
        case .executableMissing(let name):
            return "\(name) was not found. Copy the prompt or configure the CLI first."
        case .gitUnavailable:
            return "Git is unavailable. PlansBar did not start an agent session."
        case .repositoryChanged:
            return "The repository has uncommitted changes. Review them before starting an agent."
        case .gitCheckFailed:
            return "PlansBar could not check the repository worktree."
        case .gitCheckTimedOut:
            return "The repository status check timed out."
        case .terminalAutomationDenied(let reason):
            return "Terminal automation failed: \(reason)"
        }
    }
}

enum AgentLauncher {
    static func launch(
        adapter: AgentAdapter,
        repositoryPath: String,
        prompt: String
    ) async throws {
        guard adapter == .codex || adapter == .claude else {
            throw AgentLaunchError.unsupportedAdapter
        }
        let executable = try executableURL(for: adapter)
        try await Task.detached(priority: .userInitiated) {
            try ensureCleanRepository(at: repositoryPath)
        }.value

        let command = AgentLaunchCommand.terminalCommand(
            executablePath: executable.path,
            repositoryPath: repositoryPath,
            prompt: prompt
        )
        let source = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        var error: NSDictionary?
        guard NSAppleScript(source: source)?.executeAndReturnError(&error) != nil else {
            let reason = error?[NSAppleScript.errorMessage] as? String ?? "permission denied"
            throw AgentLaunchError.terminalAutomationDenied(reason)
        }
    }

    private static func executableURL(for adapter: AgentAdapter) throws -> URL {
        let name = adapter == .codex ? "codex" : "claude"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            home.appending(path: ".local/bin/\(name)")
        ]
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw AgentLaunchError.executableMissing(adapter.title)
        }
        return executable
    }

    private static func ensureCleanRepository(at path: String) throws {
        switch GitWorktreeGuard.check(repositoryPath: path) {
        case .clean: return
        case .changed: throw AgentLaunchError.repositoryChanged
        case .unavailable: throw AgentLaunchError.gitUnavailable
        case .failed: throw AgentLaunchError.gitCheckFailed
        case .timedOut: throw AgentLaunchError.gitCheckTimedOut
        }
    }
}
