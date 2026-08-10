import XCTest

@testable import PlansCore

final class GitMetadataTests: XCTestCase {
    func testParseLogKeepsNewestCommitPerFile() {
        let log = """
        \u{01}2026-08-10T10:00:00+03:00
        docs/plans/active/new.md

        \u{01}2026-08-01T10:00:00+03:00
        docs/plans/active/new.md
        docs/plans/active/old.md
        """

        let dates = GitCapability.parseLog(log)

        XCTAssertEqual(dates.count, 2)
        XCTAssertGreaterThan(
            try XCTUnwrap(dates["docs/plans/active/new.md"]),
            try XCTUnwrap(dates["docs/plans/active/old.md"])
        )
    }

    func testMissingGitReportsNoFreshnessInsteadOfFailing() {
        let capability = GitCapability(executablePath: nil)

        XCTAssertFalse(capability.isAvailable)
        XCTAssertTrue(
            capability.lastCommitDates(repositoryRoot: URL(fileURLWithPath: "/tmp")).isEmpty
        )
    }

    /// Относительный или отсутствующий configured path не принимается,
    /// но и не отключает Git: probe продолжает перебирать системных кандидатов.
    func testProbeRejectsRelativeAndMissingExecutables() {
        XCTAssertNotEqual(GitCapability.probe(configuredPath: "git").executablePath, "git")
        XCTAssertNotEqual(
            GitCapability.probe(configuredPath: "/nonexistent/git").executablePath,
            "/nonexistent/git"
        )
    }

    /// `/usr/bin/git` — Apple-shim, который без Command Line Tools открывает
    /// диалог установки, поэтому он не должен попадать в кандидаты.
    func testProbeNeverSelectsAppleShim() {
        XCTAssertNotEqual(GitCapability.probe().executablePath, "/usr/bin/git")
    }
}
