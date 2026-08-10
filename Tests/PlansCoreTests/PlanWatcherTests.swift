import XCTest

@testable import PlansCore

final class PlanWatcherTests: XCTestCase {
    private let sampleAPI = URL(fileURLWithPath: "/tmp/plansbar-watch/sample-api")
    private let mobileApp = URL(fileURLWithPath: "/tmp/plansbar-watch/mobile-app")

    func testPlanChangeRoutesToItsRepository() {
        let affected = PlanWatcher.affectedRoots(
            paths: ["/tmp/plansbar-watch/sample-api/docs/plans/active/2026-08-10-a.md"],
            roots: [sampleAPI, mobileApp]
        )

        XCTAssertEqual(affected, [sampleAPI])
    }

    func testSourceAndGitWritesAreIgnored() {
        let affected = PlanWatcher.affectedRoots(
            paths: [
                "/tmp/plansbar-watch/sample-api/.git/index",
                "/tmp/plansbar-watch/sample-api/src/main.swift",
                "/tmp/plansbar-watch/sample-api/docs/other/notes.md"
            ],
            roots: [sampleAPI, mobileApp]
        )

        XCTAssertTrue(affected.isEmpty)
    }

    func testBurstOfEditsCollapsesToAffectedRepositories() {
        let paths = (0..<50).map {
            "/tmp/plansbar-watch/sample-api/docs/plans/active/2026-08-10-plan-\($0).md"
        } + ["/tmp/plansbar-watch/mobile-app/docs/plans/backlog/2026-08-10-idea.md"]

        let affected = PlanWatcher.affectedRoots(paths: paths, roots: [sampleAPI, mobileApp])

        XCTAssertEqual(affected, [sampleAPI, mobileApp])
    }

    /// Создание `docs/plans` в подготавливаемом репозитории обязано будить
    /// индексатор, иначе состояние missing_structure никогда не обновится.
    func testCreatingPlansDirectoryWakesTheIndex() {
        let affected = PlanWatcher.affectedRoots(
            paths: ["/tmp/plansbar-watch/sample-api/docs/plans"],
            roots: [sampleAPI]
        )

        XCTAssertEqual(affected, [sampleAPI])
    }
}
