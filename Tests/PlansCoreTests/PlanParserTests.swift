import XCTest

@testable import PlansCore

final class PlanParserTests: XCTestCase {
    func testValidFixtureIgnoresNestedFencedPlan() throws {
        let file = fixture("v1/valid/2026-08-10-sample-rollout.md")
        let plan = PlanParser.parse(
            fileURL: file,
            relativePath: "docs/plans/active/2026-08-10-sample-rollout.md",
            bucket: .active
        )

        XCTAssertEqual(plan.parseState, .parsed)
        XCTAssertEqual(plan.checkboxDone, 2)
        XCTAssertEqual(plan.checkboxTotal, 3)
        XCTAssertEqual(plan.progressPercent, 67)
        XCTAssertEqual(plan.nextOpenStep, "Verify the root-relative golden output.")
        XCTAssertTrue(plan.lintErrors.isEmpty)
    }

    func testUnclosedFenceRemainsVisibleAsInvalid() throws {
        let file = fixture("v1/invalid/2026-08-10-broken-fence.md")
        let plan = PlanParser.parse(
            fileURL: file,
            relativePath: "docs/plans/active/2026-08-10-broken-fence.md",
            bucket: .active
        )

        XCTAssertEqual(plan.parseState, .invalidPlan)
        XCTAssertEqual(plan.lintErrors, ["unclosed_code_fence", "missing_required_section"])
    }

    func testAttentionStatusesRemainValidWarnings() {
        let cases = [
            ("draft", "status_draft"),
            ("blocked", "status_blocked"),
            ("paused", "status_paused")
        ]

        for (status, warning) in cases {
            let filename = "2026-08-10-\(status)-plan.md"
            let plan = PlanParser.parse(
                fileURL: fixture("v1/cases/\(filename)"),
                relativePath: "docs/plans/active/\(filename)",
                bucket: .active
            )
            XCTAssertEqual(plan.parseState, .parsed)
            XCTAssertEqual(plan.lintWarnings, [warning])
        }
    }

    func testCompletedPlanRequiresClosedStepsAndEvidence() {
        let filename = "2026-08-10-completed-plan.md"
        let plan = PlanParser.parse(
            fileURL: fixture("v1/cases/\(filename)"),
            relativePath: "docs/plans/completed/\(filename)",
            bucket: .completed
        )

        XCTAssertEqual(plan.parseState, .parsed)
        XCTAssertEqual(plan.completed, "2026-08-11")
        XCTAssertEqual(plan.checkboxDone, 1)
    }

    func testStableErrorsForMisplacedCheckboxUnsafeHTMLAndMissingSection() {
        let cases = [
            ("2026-08-10-misplaced-checkbox.md", "checkbox_outside_implementation_steps"),
            ("2026-08-10-unsafe-html.md", "raw_executable_html"),
            ("2026-08-10-missing-section.md", "missing_required_section")
        ]

        for (filename, error) in cases {
            let plan = PlanParser.parse(
                fileURL: fixture("v1/cases/\(filename)"),
                relativePath: "docs/plans/active/\(filename)",
                bucket: .active
            )
            XCTAssertEqual(plan.parseState, .invalidPlan)
            XCTAssertTrue(plan.lintErrors.contains(error))
        }
    }

    private func fixture(_ path: String) -> URL {
        Bundle.module.resourceURL!
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: path)
    }
}
