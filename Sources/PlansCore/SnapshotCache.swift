import Foundation

public enum SnapshotCache {
    public static func load(from url: URL, expectedRepositorySet: [String]) -> PlansSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(PlansSnapshot.self, from: data),
              snapshot.schemaVersion == PlansSnapshot.currentSchemaVersion,
              snapshot.repositorySet == expectedRepositorySet.sorted()
        else { return nil }
        return snapshot
    }

    public static func save(_ snapshot: PlansSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
