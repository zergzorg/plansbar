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
        guard case .output(let data) = Self.run(
            executablePath: executablePath,
            arguments: arguments,
            timeout: timeout
        ) else { return [:] }
        return Self.parseLog(String(decoding: data, as: UTF8.self))
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

    enum RunResult {
        case output(Data)
        case failed
        case timedOut
    }

    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 4 * 1024 * 1024
    ) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_OPTIONAL_LOCKS": "0"
        ]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failed
        }

        let handle = pipe.fileHandleForReading
        let collector = OutputCollector(limit: outputLimit)
        let readingFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            // Pipe дочитывается до конца даже сверх лимита: иначе Git
            // заблокируется на записи и никогда не завершится.
            while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                collector.append(chunk)
            }
            readingFinished.signal()
        }

        let deadline = DispatchTime.now() + timeout
        if readingFinished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = readingFinished.wait(timeout: .now() + 1)
            return .timedOut
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .failed }
        return .output(collector.data)
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

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard storage.count < limit else { return }
        storage.append(chunk.prefix(limit - storage.count))
    }
}
