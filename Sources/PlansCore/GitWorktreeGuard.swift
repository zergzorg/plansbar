import Foundation

public enum GitWorktreeState: String, Sendable {
    case clean
    case changed
    case unavailable
    case failed
    case timedOut = "timed_out"
}

public enum GitWorktreeGuard {
    /// Хватает одного байта вывода: любая строка `status --porcelain`
    /// означает незакоммиченные изменения.
    public static func check(
        repositoryPath: String,
        git: GitCapability = .probe(),
        timeout: TimeInterval = 5
    ) -> GitWorktreeState {
        guard let executablePath = git.executablePath else { return .unavailable }
        let result = GitCapability.run(
            executablePath: executablePath,
            arguments: ["-C", repositoryPath, "status", "--porcelain", "--untracked-files=normal"],
            timeout: timeout,
            outputLimit: 1
        )
        switch result {
        case .output(let data): return data.isEmpty ? .clean : .changed
        case .failed: return .failed
        case .timedOut: return .timedOut
        }
    }
}
