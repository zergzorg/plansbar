import Foundation
import XCTest

@testable import PlansCore

final class SnapshotCacheTests: XCTestCase {
    func testCacheRequiresCurrentSchemaAndMatchingRepositorySet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = directory.appending(path: "snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let validation = RepositoryValidator.validate(
            rootURL: repositoryFixtures.appending(path: "ready/sample-api", directoryHint: .isDirectory),
            fallbackIdentity: "sample"
        )
        let snapshot = PlansSnapshot(
            generatedAt: "2026-08-10T10:00:00Z",
            repositorySet: ["sample"],
            validations: [validation]
        )
        try SnapshotCache.save(snapshot, to: cache)

        XCTAssertEqual(
            SnapshotCache.load(from: cache, expectedRepositorySet: ["sample"])?.validations.count,
            1
        )
        XCTAssertNil(SnapshotCache.load(from: cache, expectedRepositorySet: ["other"]))

        try SnapshotCache.save(
            PlansSnapshot(schemaVersion: 2, repositorySet: ["sample"], validations: [validation]),
            to: cache
        )
        XCTAssertNil(SnapshotCache.load(from: cache, expectedRepositorySet: ["sample"]))

        try Data("broken".utf8).write(to: cache, options: .atomic)
        XCTAssertNil(SnapshotCache.load(from: cache, expectedRepositorySet: ["sample"]))
    }

    private var repositoryFixtures: URL {
        Bundle.module.resourceURL!
            .appending(path: "Fixtures/repository", directoryHint: .isDirectory)
    }
}
