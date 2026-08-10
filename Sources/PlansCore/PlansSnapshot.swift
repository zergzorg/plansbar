import Foundation

public struct PlansSnapshot: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: String
    public let repositorySet: [String]
    public let validations: [RepositoryValidation]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: String = ISO8601DateFormatter().string(from: Date()),
        repositorySet: [String],
        validations: [RepositoryValidation]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.repositorySet = repositorySet.sorted()
        self.validations = validations
    }
}
