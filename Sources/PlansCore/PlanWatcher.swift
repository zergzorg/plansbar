import CoreServices
import Foundation

/// Следит за планами зарегистрированных репозиториев через FSEvents.
/// Один поток на весь набор корней; события коалесцируются самим FSEvents,
/// поэтому отдельный таймер полного rescan не нужен.
public final class PlanWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable (Set<URL>) -> Void

    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "io.github.zergzorg.plansbar.watcher")
    private var stream: FSEventStreamRef?
    private var roots: [URL] = []
    private var handler: ChangeHandler?

    public init(latency: TimeInterval = 0.3) {
        self.latency = latency
    }

    deinit {
        tearDown()
    }

    /// Пересоздаёт поток под текущий набор корней: add/remove repository во
    /// время работы приложения не требует перезапуска.
    public func start(roots: [URL], onChange: @escaping ChangeHandler) {
        queue.sync {
            tearDown()
            self.roots = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            self.handler = onChange
            guard !self.roots.isEmpty else { return }

            // Следим за `docs`, а не за корнем репозитория: правки исходного
            // кода и служебные записи в `.git` не должны будить индексатор.
            let watchedPaths = self.roots.map { root -> String in
                let docs = root.appending(path: "docs", directoryHint: .isDirectory)
                return FileManager.default.fileExists(atPath: docs.path) ? docs.path : root.path
            }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes
            )
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, count, paths, _, _ in
                    // kFSEventStreamCreateFlagUseCFTypes отдаёт CFArray из CFString.
                    guard let info, count > 0,
                          let changed = unsafeBitCast(paths, to: NSArray.self) as? [String]
                    else { return }
                    Unmanaged<PlanWatcher>.fromOpaque(info)
                        .takeUnretainedValue()
                        .handle(paths: changed)
                },
                &context,
                watchedPaths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else { return }

            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            self.stream = stream
        }
    }

    public func stop() {
        queue.sync { tearDown() }
    }

    private func tearDown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(paths: [String]) {
        let affected = Self.affectedRoots(paths: paths, roots: roots)
        guard !affected.isEmpty, let handler else { return }
        handler(affected)
    }

    /// Событие интересно, только если оно пришло из `docs/plans` известного
    /// корня. Так atomic rename, массовые правки агента и записи в `.git`
    /// сводятся к списку репозиториев, которые действительно надо пересканировать.
    static func affectedRoots(paths: [String], roots: [URL]) -> Set<URL> {
        var affected: Set<URL> = []
        for path in paths {
            let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
            for root in roots {
                let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                guard resolved == root.path || resolved.hasPrefix(prefix) else { continue }
                let relative = resolved == root.path
                    ? ""
                    : String(resolved.dropFirst(prefix.count))
                if relative.isEmpty
                    || relative == "docs"
                    || relative == "docs/plans"
                    || relative.hasPrefix("docs/plans/") {
                    affected.insert(root)
                }
            }
        }
        return affected
    }
}
