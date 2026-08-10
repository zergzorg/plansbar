import Foundation
import XCTest

@testable import PlansCore

final class GitWorktreeGuardTests: XCTestCase {
    func testCleanAndChangedRepositoryStates() throws {
        let repository = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: repository) }

        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q"], at: repository)
        try "tracked\n".write(
            to: repository.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], at: repository)
        try runGit([
            "-c", "user.name=PlansBar Test",
            "-c", "user.email=plansbar@example.invalid",
            "commit", "-q", "-m", "fixture"
        ], at: repository)

        XCTAssertEqual(GitWorktreeGuard.check(repositoryPath: repository.path), .clean)
        try "changed\n".write(
            to: repository.appending(path: "untracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(GitWorktreeGuard.check(repositoryPath: repository.path), .changed)
    }

    private func runGit(_ arguments: [String], at repository: URL) throws {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/git"
        )
        process.arguments = ["-C", repository.path] + arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
