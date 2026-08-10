import XCTest

@testable import PlansCore

final class PlanSearchTests: XCTestCase {
    func testTitleRepositoryAndNextStepRankingIsNormalized() {
        XCTAssertEqual(rank("resume", title: "Résumé rollout"), 0)
        XCTAssertEqual(rank("roll", title: "Résumé rollout"), 1)
        XCTAssertEqual(rank("sample", repository: "sample-api"), 2)
        XCTAssertEqual(rank("verify", nextStep: "Verify the fixture"), 3)
        XCTAssertNil(rank("missing"))
    }

    func testLifecycleOrdering() {
        XCTAssertLessThan(PlanSearch.lifecycleRank("active"), PlanSearch.lifecycleRank("backlog"))
        XCTAssertLessThan(PlanSearch.lifecycleRank("backlog"), PlanSearch.lifecycleRank("completed"))
    }

    private func rank(
        _ query: String,
        title: String = "Plan",
        repository: String = "repo",
        nextStep: String? = nil
    ) -> Int? {
        PlanSearch.rank(
            query: query,
            title: title,
            repository: repository,
            nextStep: nextStep
        )
    }
}
