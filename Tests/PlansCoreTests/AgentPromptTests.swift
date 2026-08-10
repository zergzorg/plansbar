import XCTest

@testable import PlansCore

final class AgentPromptTests: XCTestCase {
    private let sample = AgentPromptInput(
        planPath: "docs/plans/active/2026-08-10-sample.md",
        repositoryName: "sample-api",
        repositoryPath: "~/Code/sample-api",
        title: "Sample plan",
        nextStep: "Add the first migration",
        completedSteps: 2,
        totalSteps: 5
    )

    func testEnglishPromptCarriesPlanContext() {
        let prompt = AgentPrompt.make(sample)

        XCTAssertTrue(prompt.contains("docs/plans/active/2026-08-10-sample.md"))
        XCTAssertTrue(prompt.contains("sample-api"))
        XCTAssertTrue(prompt.contains("2 of 5 steps complete"))
        XCTAssertTrue(prompt.contains("Add the first migration"))
    }

    func testRussianPromptCarriesTheSameContext() {
        let prompt = AgentPrompt.make(sample, language: .russian)

        XCTAssertTrue(prompt.contains("docs/plans/active/2026-08-10-sample.md"))
        XCTAssertTrue(prompt.contains("выполнено 2 из 5 шагов"))
        XCTAssertTrue(prompt.contains("Add the first migration"))
    }

    func testPlanWithoutNextStepAsksForReview() {
        let input = AgentPromptInput(
            planPath: sample.planPath,
            repositoryName: sample.repositoryName,
            repositoryPath: sample.repositoryPath,
            title: sample.title,
            nextStep: nil,
            completedSteps: 5,
            totalSteps: 5
        )

        XCTAssertTrue(AgentPrompt.make(input).contains("Review and finish this plan."))
        XCTAssertTrue(AgentPrompt.make(input, language: .russian).contains("Проверь и заверши этот план."))
    }
}
