import Darwin
import Foundation

private struct ExpectedPlan: Decodable, Equatable {
    let schemaVersion: Int
    let path: String
    let bucket: String
    let format: String
    let parseState: String
    let planVersion: String
    let title: String
    let status: String
    let created: String
    let completed: String
    let scope: String
    let checkboxTotal: Int
    let checkboxDone: Int
    let progressPercent: Int?
    let nextOpenStep: String?
    let lintErrors: [String]
    let lintWarnings: [String]

    init(_ plan: PlanRecord) {
        schemaVersion = 1
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
}

private struct ExpectedRepositoryState: Decodable, Equatable {
    let root: String
    let state: String
    let candidatePlanPaths: [String]
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum FixtureVerifier {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw VerificationFailure(description: "Usage: verify-fixtures <fixtures-directory>")
            }
            let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try verifyPlan(
                fixtures: fixtures,
                source: "v1/valid/2026-08-10-sample-rollout.md",
                expected: "expected/valid-sample.json",
                relativePath: "docs/plans/active/2026-08-10-sample-rollout.md",
                bucket: .active
            )
            try verifyPlan(
                fixtures: fixtures,
                source: "v1/invalid/2026-08-10-broken-fence.md",
                expected: "expected/invalid-broken-fence.json",
                relativePath: "docs/plans/active/2026-08-10-broken-fence.md",
                bucket: .active
            )
            try verifyRepositoryStates(fixtures: fixtures)
            try verifySymlinkNormalizedRepository(fixtures: fixtures)
            try verifyRepositoryIdentity()
            try verifySnapshotCache(fixtures: fixtures)
            try verifySearch()
            try verifyAgentLaunchCommand()
            try verifyGitWorktreeGuard()
            try verifyNewIdeaPrompt()
            try verifyGitFreshnessParsing()
            try verifyWatcherRouting()
            try verifyPartialBucketScan(fixtures: fixtures)
            try verifyPartialStructureStillIndexes(fixtures: fixtures)
            print("Fixture verification passed.")
        } catch {
            fputs("Fixture verification failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func verifyPlan(
        fixtures: URL,
        source: String,
        expected: String,
        relativePath: String,
        bucket: PlanBucket
    ) throws {
        let expectedReport: ExpectedPlan = try decode(fixtures.appending(path: expected))
        let plan = PlanParser.parse(
            fileURL: fixtures.appending(path: source),
            relativePath: relativePath,
            bucket: bucket
        )
        guard ExpectedPlan(plan) == expectedReport else {
            throw VerificationFailure(description: "Golden plan mismatch: \(expected)")
        }
    }

    private static func verifyRepositoryStates(fixtures: URL) throws {
        let expected: [ExpectedRepositoryState] = try decode(
            fixtures.appending(path: "expected/repository-states.json")
        )
        let repositoryFixtures = fixtures.appending(path: "repository", directoryHint: .isDirectory)
        let actual = expected.map { item in
            let validation = RepositoryValidator.validate(
                rootURL: repositoryFixtures.appending(path: item.root.replacingOccurrences(of: "repository/", with: ""))
            )
            return ExpectedRepositoryState(
                root: item.root,
                state: validation.state.rawValue,
                candidatePlanPaths: validation.plans.map(\.relativePath)
            )
        }
        guard actual == expected else {
            throw VerificationFailure(description: "Repository state golden mismatch")
        }
    }

    private static func verifySymlinkNormalizedRepository(fixtures: URL) throws {
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appending(path: "plansbar-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(
            at: fixtures.appending(path: "repository/ready/sample-api", directoryHint: .isDirectory),
            to: temporary
        )
        let validation = RepositoryValidator.validate(rootURL: temporary)
        guard validation.state == .ready,
              validation.plans.first?.relativePath == "docs/plans/active/2026-08-10-sample-rollout.md"
        else {
            throw VerificationFailure(description: "Symlink-normalized repository lost stable keys")
        }
    }

    private static func verifyRepositoryIdentity() throws {
        let first = try temporaryRepository(remote: "git@github.com:zergzorg/plansbar.git")
        let second = try temporaryRepository(remote: "git@github.com:zergzorg/plansbar.git")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let firstIdentity = RepositoryIdentity.resolve(rootURL: first, fallback: "first")
        let secondIdentity = RepositoryIdentity.resolve(rootURL: second, fallback: "second")
        guard firstIdentity == secondIdentity, firstIdentity.kind == .gitRemote else {
            throw VerificationFailure(description: "Confirmed Git clones do not share identity")
        }

        let local = URL(fileURLWithPath: "/tmp/plansbar-local", isDirectory: true)
        guard RepositoryIdentity.resolve(rootURL: local, fallback: "first")
            != RepositoryIdentity.resolve(rootURL: local, fallback: "second")
        else {
            throw VerificationFailure(description: "Unconfirmed local registrations share identity")
        }
    }

    private static func verifySnapshotCache(fixtures: URL) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = directory.appending(path: "snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let validation = RepositoryValidator.validate(
            rootURL: fixtures.appending(path: "repository/ready/sample-api", directoryHint: .isDirectory),
            fallbackIdentity: "sample"
        )
        try SnapshotCache.save(
            PlansSnapshot(repositorySet: ["sample"], validations: [validation]),
            to: cache
        )
        guard SnapshotCache.load(from: cache, expectedRepositorySet: ["sample"]) != nil,
              SnapshotCache.load(from: cache, expectedRepositorySet: ["other"]) == nil
        else {
            throw VerificationFailure(description: "Snapshot repository-set gate failed")
        }

        try SnapshotCache.save(
            PlansSnapshot(schemaVersion: 2, repositorySet: ["sample"], validations: [validation]),
            to: cache
        )
        guard SnapshotCache.load(from: cache, expectedRepositorySet: ["sample"]) == nil else {
            throw VerificationFailure(description: "Snapshot schema gate failed")
        }

        try Data("broken".utf8).write(to: cache, options: .atomic)
        guard SnapshotCache.load(from: cache, expectedRepositorySet: ["sample"]) == nil else {
            throw VerificationFailure(description: "Corrupt snapshot was accepted")
        }
    }

    private static func temporaryRepository(remote: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let git = root.appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = \(remote)\n"
            .write(to: git.appending(path: "config"), atomically: true, encoding: .utf8)
        return root
    }

    private static func verifySearch() throws {
        guard PlanSearch.rank(
            query: "resume",
            title: "Résumé rollout",
            repository: "sample-api",
            nextStep: nil
        ) == 0,
        PlanSearch.rank(
            query: "sample",
            title: "Rollout",
            repository: "sample-api",
            nextStep: nil
        ) == 2,
        PlanSearch.rank(
            query: "verify",
            title: "Rollout",
            repository: "sample-api",
            nextStep: "Verify fixtures"
        ) == 3,
        PlanSearch.lifecycleRank("active") < PlanSearch.lifecycleRank("backlog"),
        PlanSearch.lifecycleRank("backlog") < PlanSearch.lifecycleRank("completed")
        else {
            throw VerificationFailure(description: "Plan search ranking failed")
        }
    }

    private static func verifyAgentLaunchCommand() throws {
        let values = [
            "path with spaces",
            "apostrophe's repo",
            "Юникод",
            "line one\nline two",
            "--leading-dash"
        ]
        for value in values {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "/usr/bin/printf %s \(AgentLaunchCommand.shellQuote(value))"]
            process.standardOutput = output
            try process.run()
            process.waitUntilExit()
            guard String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == value else {
                throw VerificationFailure(description: "Agent shell quoting failed")
            }
        }

        let prompt = "private prompt\nwith lines"
        let command = AgentLaunchCommand.terminalCommand(
            executablePath: "/opt/homebrew/bin/codex",
            repositoryPath: "/tmp/repo with spaces",
            prompt: prompt
        )
        guard !command.contains(prompt), command.unicodeScalars.allSatisfy(\.isASCII) else {
            throw VerificationFailure(description: "Terminal command exposes literal prompt")
        }
    }

    private static func verifyGitWorktreeGuard() throws {
        let repository = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: repository) }
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q"], at: repository)
        try "tracked\n".write(
            to: repository.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], at: repository)
        try runGit([
            "-c", "user.name=PlansBar Test",
            "-c", "user.email=plansbar@example.invalid",
            "commit", "-q", "-m", "fixture"
        ], at: repository)
        guard GitWorktreeGuard.check(repositoryPath: repository.path) == .clean else {
            throw VerificationFailure(description: "Clean Git repository was blocked")
        }

        try "changed\n".write(
            to: repository.appending(path: "untracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        guard GitWorktreeGuard.check(repositoryPath: repository.path) == .changed else {
            throw VerificationFailure(description: "Dirty Git repository was not blocked")
        }
    }

    private static func runGit(_ arguments: [String], at repository: URL) throws {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/git"
        )
        process.arguments = ["-C", repository.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VerificationFailure(description: "Unable to create Git guard fixture")
        }
    }

    private static func verifyNewIdeaPrompt() throws {
        let input = NewIdeaPromptInput(
            repositoryName: "sample-api",
            repositoryPath: "~/Code/sample-api",
            idea: "Add release health"
        )
        for prompt in [
            AgentPrompt.makeNewIdea(input),
            AgentPrompt.makeNewIdea(input, language: .russian)
        ] {
            guard prompt.contains("sample-api"),
                  prompt.contains("Add release health"),
                  prompt.contains("docs/plans/backlog"),
                  !prompt.contains("Codex"),
                  !prompt.contains("Claude")
            else {
                throw VerificationFailure(description: "New idea prompt lost provider-neutral context")
            }
        }
    }

    private static func verifyGitFreshnessParsing() throws {
        let log = """
        \u{01}2026-08-10T10:00:00+03:00
        docs/plans/active/new.md

        \u{01}2026-08-01T10:00:00+03:00
        docs/plans/active/new.md
        docs/plans/active/old.md
        """
        let dates = GitCapability.parseLog(log)
        guard dates.count == 2,
              let newest = dates["docs/plans/active/new.md"],
              let older = dates["docs/plans/active/old.md"],
              newest > older
        else {
            throw VerificationFailure(description: "Git log parsing lost the newest commit per file")
        }
        // Отсутствующий Git не должен давать частичные данные.
        guard GitCapability(executablePath: nil)
            .lastCommitDates(repositoryRoot: URL(fileURLWithPath: "/tmp"))
            .isEmpty
        else {
            throw VerificationFailure(description: "Missing Git produced freshness data")
        }
    }

    private static func verifyWatcherRouting() throws {
        let root = URL(fileURLWithPath: "/tmp/plansbar-watch/sample-api")
        let other = URL(fileURLWithPath: "/tmp/plansbar-watch/mobile-app")
        let affected = PlanWatcher.affectedRoots(
            paths: [
                "/tmp/plansbar-watch/sample-api/docs/plans/active/2026-08-10-a.md",
                "/tmp/plansbar-watch/sample-api/.git/index",
                "/tmp/plansbar-watch/sample-api/src/main.swift",
                "/tmp/plansbar-watch/mobile-app/docs/other/notes.md"
            ],
            roots: [root, other]
        )
        guard affected == [root] else {
            throw VerificationFailure(
                description: "Watcher routed events outside docs/plans or missed a plan change"
            )
        }
    }

    /// Git не хранит пустые каталоги: репозиторий без `backlog` обязан
    /// индексироваться, а не прятать планы за missing_structure.
    private static func verifyPartialStructureStillIndexes(fixtures: URL) throws {
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "plansbar-partial-\(UUID().uuidString)", directoryHint: .isDirectory)
        let active = sandbox.appending(path: "docs/plans/active", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let source = fixtures.appending(path: "v1/valid/2026-08-10-sample-rollout.md")
        try FileManager.default.copyItem(
            at: source,
            to: active.appending(path: "2026-08-10-sample-rollout.md")
        )

        let validation = RepositoryValidator.validate(rootURL: sandbox)
        guard validation.state == .ready, validation.plans.count == 1 else {
            throw VerificationFailure(
                description: "Repository without a backlog directory was not indexed"
            )
        }
        guard validation.missingPaths.contains("docs/plans/backlog") else {
            throw VerificationFailure(description: "Missing bucket was not reported")
        }

        // Полностью отсутствующая структура по-прежнему блокирует.
        let empty = sandbox.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        guard RepositoryValidator.validate(rootURL: empty).state == .missingStructure else {
            throw VerificationFailure(description: "Empty repository was not reported as missing structure")
        }
    }

    private static func verifyPartialBucketScan(fixtures: URL) throws {
        let root = fixtures.appending(path: "repository/ready/sample-api", directoryHint: .isDirectory)
        let queueOnly = RepositoryValidator.validate(rootURL: root, buckets: [.active, .backlog])
        let full = RepositoryValidator.validate(rootURL: root)
        guard queueOnly.plans.allSatisfy({ $0.bucket != .completed }) else {
            throw VerificationFailure(description: "Queue-only scan included the completed archive")
        }
        guard full.plans.count >= queueOnly.plans.count else {
            throw VerificationFailure(description: "Full scan lost plans found by the queue-only scan")
        }
    }

    private static func decode<Value: Decodable>(_ url: URL) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Value.self, from: Data(contentsOf: url))
    }
}
