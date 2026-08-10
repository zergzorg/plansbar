import Foundation

/// Доступность Git проверяется один раз и передаётся значением, поэтому
/// сканирование не зависит от глобального изменяемого состояния.
public struct GitCapability: Sendable {
    public let executablePath: String?

    public var isAvailable: Bool { executablePath != nil }

    public init(executablePath: String?) {
        self.executablePath = executablePath
    }

    /// `/usr/bin/git` намеренно не входит в список кандидатов: это Apple-shim,
    /// который без установленных Command Line Tools открывает системный диалог
    /// установки. Проверяем только реальные исполняемые файлы.
    private static let candidatePaths = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
    ]

    public static func probe(configuredPath: String? = nil) -> GitCapability {
        let candidates = [configuredPath].compactMap { $0 } + candidatePaths
        for path in candidates where isExecutable(path) {
            return GitCapability(executablePath: path)
        }
        return GitCapability(executablePath: nil)
    }

    private static func isExecutable(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Одна проверка на репозиторий вместо процесса на каждый план: `git log`
    /// с `--name-only` отдаёт дату последнего касания сразу для всех файлов.
    /// Отсутствие Git, таймаут или ошибка репозитория дают пустой результат —
    /// вызывающая сторона откатывается на mtime, а scan не падает.
    public func lastCommitDates(
        repositoryRoot: URL,
        relativeDirectory: String = "docs/plans",
        commitLimit: Int = 2000,
        timeout: TimeInterval = 5
    ) -> [String: Date] {
        guard let executablePath else { return [:] }
        let arguments = [
            "-C", repositoryRoot.path,
            "log",
            "-n", String(commitLimit),
            "--format=%x01%cI",
            "--name-only",
            "--", relativeDirectory
        ]
        guard let output = Self.run(
            executablePath: executablePath,
            arguments: arguments,
            timeout: timeout
        ) else { return [:] }
        return Self.parseLog(output)
    }

    static func parseLog(_ output: String) -> [String: Date] {
        let formatter = ISO8601DateFormatter()
        var dates: [String: Date] = [:]
        var currentDate: Date?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == "\u{01}" {
                currentDate = formatter.date(from: String(line.dropFirst()))
                continue
            }
            let path = String(line)
            guard !path.isEmpty, let currentDate else { continue }
            // git log идёт от новых коммитов к старым, поэтому первое
            // встреченное значение и есть последнее изменение файла.
            if dates[path] == nil { dates[path] = currentDate }
        }
        return dates
    }

    private static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 4 * 1024 * 1024
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let handle = pipe.fileHandleForReading
        let collector = OutputCollector(limit: outputLimit)
        let readingFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                if collector.append(chunk) { break }
            }
            readingFinished.signal()
        }

        let deadline = DispatchTime.now() + timeout
        if readingFinished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = readingFinished.wait(timeout: .now() + 1)
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: collector.data, encoding: .utf8)
    }
}

/// Ограничивает объём вычитанного вывода, чтобы огромная история не съела память.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()

    init(limit: Int) {
        self.limit = limit
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Возвращает `true`, когда лимит исчерпан и читать дальше не нужно.
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storage.count < limit else { return true }
        storage.append(chunk.prefix(limit - storage.count))
        return storage.count >= limit
    }
}
