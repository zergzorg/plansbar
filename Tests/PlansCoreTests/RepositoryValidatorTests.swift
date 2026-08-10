import XCTest

@testable import PlansCore

final class RepositoryValidatorTests: XCTestCase {
    func testRepositoryStates() {
        XCTAssertEqual(validate("ready/sample-api").state, .ready)
        XCTAssertEqual(validate("missing-structure/mobile-app").state, .missingStructure)
        XCTAssertEqual(validate("invalid-plans/sample-api").state, .invalidPlans)
        XCTAssertEqual(validate("ambiguous-completed/sample-api").state, .invalidPlans)

        let moved = repositoryFixtures.appending(path: "inaccessible/moved-repo", directoryHint: .isDirectory)
        XCTAssertEqual(RepositoryValidator.validate(rootURL: moved).state, .inaccessible)
    }

    func testPreparationPromptIsOnlyAvailableWhenAgentWorkCanHelp() {
        XCTAssertNil(RepositoryPreparationPrompt.make(validate("ready/sample-api")))
        XCTAssertNotNil(RepositoryPreparationPrompt.make(validate("missing-structure/mobile-app")))

        let invalid = validate("invalid-plans/sample-api")
        let prompt = RepositoryPreparationPrompt.make(invalid)
        XCTAssertTrue(prompt?.contains("\"validation_state\" : \"invalid_plans\"") == true)
        XCTAssertTrue(prompt?.contains("docs/plans/active/2026-08-10-old-plan.md") == true)
    }

    private var repositoryFixtures: URL {
        Bundle.module.resourceURL!
            .appending(path: "Fixtures/repository", directoryHint: .isDirectory)
    }

    private func validate(_ path: String) -> RepositoryValidation {
        RepositoryValidator.validate(rootURL: repositoryFixtures.appending(path: path, directoryHint: .isDirectory))
    }
}
