import Foundation

public enum GitWorktreeState: String, Sendable {
    case clean
    case changed
    case unavailable
    case failed
    case timedOut = "timed_out"
}

public enum GitWorktreeGuard {
    private static let gitURL: URL? = [
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
    ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        .map { URL(fileURLWithPath: $0) }

    public static func check(repositoryPath: String, timeout: TimeInterval = 5) -> GitWorktreeState {
        guard let gitURL else { return .unavailable }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            "set -o pipefail; \"$PLANSBAR_GIT\" -C \"$PLANSBAR_REPOSITORY\" status --porcelain --untracked-files=normal | /usr/bin/head -n 1"
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PLANSBAR_GIT": gitURL.path,
            "PLANSBAR_REPOSITORY": repositoryPath,
            "GIT_OPTIONAL_LOCKS": "0"
        ]) { _, new in new }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .failed
        }
        let deadline = DispatchTime.now() + .milliseconds(max(1, Int(timeout * 1_000)))
        guard finished.wait(timeout: deadline) == .success else {
            process.terminate()
            return .timedOut
        }
        guard process.terminationStatus == 0 else { return .failed }
        return output.fileHandleForReading.readDataToEndOfFile().isEmpty ? .clean : .changed
    }
}
