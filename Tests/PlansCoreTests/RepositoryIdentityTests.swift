import Foundation
import XCTest

@testable import PlansCore

final class RepositoryIdentityTests: XCTestCase {
    func testOnlyConfirmedGitRemoteCollapsesClones() throws {
        let first = try repository(remote: "git@github.com:zergzorg/plansbar.git")
        let second = try repository(remote: "git@github.com:zergzorg/plansbar.git")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let firstIdentity = RepositoryIdentity.resolve(rootURL: first, fallback: "first")
        let secondIdentity = RepositoryIdentity.resolve(rootURL: second, fallback: "second")

        XCTAssertEqual(firstIdentity, secondIdentity)
        XCTAssertEqual(firstIdentity.kind, .gitRemote)
    }

    func testRegistrationsRemainDistinctWithoutGitIdentity() {
        let root = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        XCTAssertNotEqual(
            RepositoryIdentity.resolve(rootURL: root, fallback: "first"),
            RepositoryIdentity.resolve(rootURL: root, fallback: "second")
        )
    }

    private func repository(remote: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let git = root.appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = \(remote)\n"
            .write(to: git.appending(path: "config"), atomically: true, encoding: .utf8)
        return root
    }
}
