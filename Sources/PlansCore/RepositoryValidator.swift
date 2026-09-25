import Foundation

public enum RepositoryValidator {
    private static let excludedDirectories: Set<String> = [
        "artifacts", "templates", "assets", "temp_files", ".reviews"
    ]

    public static func validate(
        rootURL: URL,
        fallbackIdentity: String? = nil,
        now: Date = Date(),
        buckets: [PlanBucket] = PlanBucket.allCases,
        git: GitCapability = GitCapability(executablePath: nil)
    ) -> RepositoryValidation {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let identity = RepositoryIdentity.resolve(rootURL: root, fallback: fallbackIdentity)
        let name = root.lastPathComponent
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: root.path)
        else {
            return RepositoryValidation(
                identity: identity,
                rootURL: root,
                name: name,
                state: .inaccessible
            )
        }

        let plansRoot = root.appending(path: "docs/plans", directoryHint: .isDirectory)
        let missingPaths = PlanBucket.allCases.compactMap { bucket -> String? in
            let relative = "docs/plans/\(bucket.rawValue)"
            let url = root.appending(path: relative, directoryHint: .isDirectory)
            var bucketIsDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &bucketIsDirectory)
                && bucketIsDirectory.boolValue ? nil : relative
        }
        // Git не хранит пустые каталоги, поэтому отсутствие, например, `backlog`
        // — обычное состояние живого репозитория, а не сломанная структура.
        // Блокируем только когда не найдено ни одного bucket: иначе валидные
        // планы из существующих каталогов просто исчезли бы из индекса.
        let presentBuckets = buckets.filter { !missingPaths.contains("docs/plans/\($0.rawValue)") }
        guard missingPaths.count < PlanBucket.allCases.count else {
            return RepositoryValidation(
                identity: identity,
                rootURL: root,
                name: name,
                state: .missingStructure,
                missingPaths: missingPaths
            )
        }

        var plans: [PlanRecord] = []
        do {
            for bucket in presentBuckets {
                let bucketURL = plansRoot.appending(path: bucket.rawValue, directoryHint: .isDirectory)
                plans.append(contentsOf: try scanBucket(bucketURL, rootURL: root, bucket: bucket, now: now))
            }
        } catch {
            return RepositoryValidation(
                identity: identity,
                rootURL: root,
                name: name,
                state: .inaccessible
            )
        }
        plans.sort { $0.relativePath < $1.relativePath }
        plans = applyGitFreshness(to: plans, rootURL: root, git: git, now: now)

        return RepositoryValidation(
            identity: identity,
            rootURL: root,
            name: name,
            state: plans.allSatisfy({ $0.parseState == .parsed }) ? .ready : .invalidPlans,
            missingPaths: missingPaths,
            plans: plans
        )
    }

    /// Git недоступен, вышел по таймауту или ничего не знает о файле —
    /// freshness остаётся тем, что дал mtime, а сканирование не прерывается.
    private static func applyGitFreshness(
        to plans: [PlanRecord],
        rootURL: URL,
        git: GitCapability,
        now: Date
    ) -> [PlanRecord] {
        guard git.isAvailable else { return plans }
        // Каталог без `.git` не даст freshness, но стоит запуска процесса,
        // поэтому такие корни пропускаем до вызова Git.
        let gitPath = rootURL.appending(path: ".git", directoryHint: .isDirectory).path
        guard FileManager.default.fileExists(atPath: gitPath) else { return plans }
        let commitDates = git.lastCommitDates(repositoryRoot: rootURL)
        guard !commitDates.isEmpty else { return plans }
        return plans.map { plan in
            guard let date = commitDates[plan.relativePath] else { return plan }
            let days = Calendar.current.dateComponents([.day], from: date, to: now).day
            return plan.withDaysSinceModified(days.map { max(0, $0) })
        }
    }

    private static func scanBucket(
        _ bucketURL: URL,
        rootURL: URL,
        bucket: PlanBucket,
        now: Date
    ) throws -> [PlanRecord] {
        var plans: [PlanRecord] = []
        try scanDirectory(bucketURL, rootURL: rootURL, bucket: bucket, now: now, plans: &plans)
        return plans
    }

    private static func scanDirectory(
        _ directoryURL: URL,
        rootURL: URL,
        bucket: PlanBucket,
        now: Date,
        plans: inout [PlanRecord]
    ) throws {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey
        ]
        let entries = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        for entryURL in entries {
            let values = try entryURL.resourceValues(forKeys: keys)
            if values.isHidden == true || values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if !excludedDirectories.contains(entryURL.lastPathComponent) {
                    try scanDirectory(entryURL, rootURL: rootURL, bucket: bucket, now: now, plans: &plans)
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let file = entryURL.lastPathComponent
            if file == "README.md" || file == ".gitkeep" || file.hasPrefix(".") { continue }
            let extensionName = entryURL.pathExtension.lowercased()
            guard extensionName == "md" || extensionName == "html" else { continue }

            let entryPath = entryURL.standardizedFileURL.resolvingSymlinksInPath().path
            let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            let relativePath = entryPath.hasPrefix(prefix)
                ? String(entryPath.dropFirst(prefix.count))
                : entryURL.lastPathComponent
            if extensionName == "md" {
                plans.append(PlanParser.parse(
                    fileURL: entryURL,
                    relativePath: relativePath,
                    bucket: bucket,
                    now: now
                ))
            } else {
                plans.append(PlanParser.invalidRecord(
                    fileURL: entryURL,
                    relativePath: relativePath,
                    bucket: bucket,
                    errors: ["unsupported_plan_version"]
                ))
            }
        }
    }
}
