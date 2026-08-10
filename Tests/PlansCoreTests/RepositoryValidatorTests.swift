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

    func testRepositoryUnderSymlinkedSystemPathKeepsRootRelativeKeys() throws {
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appending(path: "plansbar-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(
            at: repositoryFixtures.appending(path: "ready/sample-api", directoryHint: .isDirectory),
            to: temporary
        )

        let validation = RepositoryValidator.validate(rootURL: temporary)
        XCTAssertEqual(validation.state, .ready)
        XCTAssertEqual(
            validation.plans.first?.relativePath,
            "docs/plans/active/2026-08-10-sample-rollout.md"
        )
    }

    /// Git не хранит пустые каталоги, поэтому репозиторий без `backlog`
    /// обязан индексироваться, а недостающий bucket — только сообщаться.
    func testRepositoryWithoutBacklogDirectoryStillIndexes() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appending(path: "plansbar-partial-\(UUID().uuidString)", directoryHint: .isDirectory)
        let active = sandbox.appending(path: "docs/plans/active", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.copyItem(
            at: repositoryFixtures.appending(
                path: "ready/sample-api/docs/plans/active/2026-08-10-sample-rollout.md"
            ),
            to: active.appending(path: "2026-08-10-sample-rollout.md")
        )

        let validation = RepositoryValidator.validate(rootURL: sandbox)

        XCTAssertEqual(validation.state, .ready)
        XCTAssertEqual(validation.plans.count, 1)
        XCTAssertTrue(validation.missingPaths.contains("docs/plans/backlog"))
    }

    func testRepositoryWithoutAnyBucketIsMissingStructure() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appending(path: "plansbar-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        XCTAssertEqual(RepositoryValidator.validate(rootURL: sandbox).state, .missingStructure)
    }

    func testQueueOnlyScanSkipsCompletedArchive() {
        let queueOnly = RepositoryValidator.validate(
            rootURL: repositoryFixtures.appending(path: "ready/sample-api", directoryHint: .isDirectory),
            buckets: [.active, .backlog]
        )

        XCTAssertTrue(queueOnly.plans.allSatisfy { $0.bucket != .completed })
    }

    private var repositoryFixtures: URL {
        Bundle.module.resourceURL!
            .appending(path: "Fixtures/repository", directoryHint: .isDirectory)
    }

    private func validate(_ path: String) -> RepositoryValidation {
        RepositoryValidator.validate(rootURL: repositoryFixtures.appending(path: path, directoryHint: .isDirectory))
    }
}
