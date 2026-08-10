import Foundation

public enum PlanBucket: String, CaseIterable, Codable, Sendable {
    case backlog
    case active
    case completed
}

public enum PlanParseState: String, Codable, Sendable {
    case parsed
    case invalidPlan = "invalid_plan"
}

public enum RepositoryValidationState: String, Codable, Sendable {
    case ready
    case missingStructure = "missing_structure"
    case invalidPlans = "invalid_plans"
    case inaccessible
}

public struct PlanRecord: Identifiable, Codable, Sendable {
    public let relativePath: String
    public let absolutePath: String
    public let bucket: PlanBucket
    public let parseState: PlanParseState
    public let planVersion: String
    public let title: String
    public let status: String
    public let created: String
    public let completed: String
    public let scope: String
    public let checkboxTotal: Int
    public let checkboxDone: Int
    public let progressPercent: Int?
    public let nextOpenStep: String?
    public let lintErrors: [String]
    public let lintWarnings: [String]
    public let daysSinceModified: Int?

    public var id: String { relativePath }

    public init(
        relativePath: String,
        absolutePath: String,
        bucket: PlanBucket,
        parseState: PlanParseState,
        planVersion: String,
        title: String,
        status: String,
        created: String,
        completed: String,
        scope: String,
        checkboxTotal: Int,
        checkboxDone: Int,
        progressPercent: Int?,
        nextOpenStep: String?,
        lintErrors: [String],
        lintWarnings: [String],
        daysSinceModified: Int?
    ) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.bucket = bucket
        self.parseState = parseState
        self.planVersion = planVersion
        self.title = title
        self.status = status
        self.created = created
        self.completed = completed
        self.scope = scope
        self.checkboxTotal = checkboxTotal
        self.checkboxDone = checkboxDone
        self.progressPercent = progressPercent
        self.nextOpenStep = nextOpenStep
        self.lintErrors = lintErrors
        self.lintWarnings = lintWarnings
        self.daysSinceModified = daysSinceModified
    }

    /// Git знает дату последнего коммита точнее, чем mtime рабочего дерева,
    /// поэтому freshness уточняется после сканирования буфера.
    public func withDaysSinceModified(_ days: Int?) -> PlanRecord {
        PlanRecord(
            relativePath: relativePath,
            absolutePath: absolutePath,
            bucket: bucket,
            parseState: parseState,
            planVersion: planVersion,
            title: title,
            status: status,
            created: created,
            completed: completed,
            scope: scope,
            checkboxTotal: checkboxTotal,
            checkboxDone: checkboxDone,
            progressPercent: progressPercent,
            nextOpenStep: nextOpenStep,
            lintErrors: lintErrors,
            lintWarnings: lintWarnings,
            daysSinceModified: days
        )
    }
}

public struct RepositoryValidation: Codable, Sendable {
    public let identity: RepositoryIdentity
    public let rootURL: URL
    public let name: String
    public let state: RepositoryValidationState
    public let missingPaths: [String]
    public let plans: [PlanRecord]

    public init(
        identity: RepositoryIdentity,
        rootURL: URL,
        name: String,
        state: RepositoryValidationState,
        missingPaths: [String] = [],
        plans: [PlanRecord] = []
    ) {
        self.identity = identity
        self.rootURL = rootURL
        self.name = name
        self.state = state
        self.missingPaths = missingPaths
        self.plans = plans
    }
}

public struct PlanReport: Codable, Sendable {
    public let path: String
    public let bucket: String
    public let format: String
    public let parseState: String
    public let planVersion: String
    public let title: String
    public let status: String
    public let created: String
    public let completed: String
    public let scope: String
    public let checkboxTotal: Int
    public let checkboxDone: Int
    public let progressPercent: Int?
    public let nextOpenStep: String?
    public let lintErrors: [String]
    public let lintWarnings: [String]

    public init(_ plan: PlanRecord) {
        path = plan.relativePath
        bucket = plan.bucket.rawValue
        format = "v1"
        parseState = plan.parseState.rawValue
        planVersion = plan.planVersion
        title = plan.title
        status = plan.status
        created = plan.created
        completed = plan.completed
        scope = plan.scope
        checkboxTotal = plan.checkboxTotal
        checkboxDone = plan.checkboxDone
        progressPercent = plan.progressPercent
        nextOpenStep = plan.nextOpenStep
        lintErrors = plan.lintErrors
        lintWarnings = plan.lintWarnings
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(bucket, forKey: .bucket)
        try container.encode(format, forKey: .format)
        try container.encode(parseState, forKey: .parseState)
        try container.encode(planVersion, forKey: .planVersion)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(created, forKey: .created)
        try container.encode(completed, forKey: .completed)
        try container.encode(scope, forKey: .scope)
        try container.encode(checkboxTotal, forKey: .checkboxTotal)
        try container.encode(checkboxDone, forKey: .checkboxDone)
        if let progressPercent {
            try container.encode(progressPercent, forKey: .progressPercent)
        } else {
            try container.encodeNil(forKey: .progressPercent)
        }
        if let nextOpenStep {
            try container.encode(nextOpenStep, forKey: .nextOpenStep)
        } else {
            try container.encodeNil(forKey: .nextOpenStep)
        }
        try container.encode(lintErrors, forKey: .lintErrors)
        try container.encode(lintWarnings, forKey: .lintWarnings)
    }
}

public struct RepositoryReport: Codable, Sendable {
    public let schemaVersion: Int
    public let repository: String
    public let state: RepositoryValidationState
    public let missingPaths: [String]
    public let plans: [PlanReport]

    public init(_ validation: RepositoryValidation) {
        schemaVersion = 1
        repository = validation.name
        state = validation.state
        missingPaths = validation.missingPaths
        plans = validation.plans.map(PlanReport.init)
    }
}
