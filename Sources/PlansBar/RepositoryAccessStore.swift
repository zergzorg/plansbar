import AppKit
import Foundation

struct RegisteredRepository: Codable, Identifiable, Equatable {
    let id: UUID
    let path: String
    let bookmark: Data

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct ResolvedRepository: Sendable {
    let registrationID: String
    let url: URL
}

@MainActor
final class RepositoryAccessStore: ObservableObject {
    @Published private(set) var repositories: [RegisteredRepository] = []

    let applicationSupportURL: URL
    private let storageURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        applicationSupportURL = base
            .appending(path: "io.github.zergzorg.plansbar", directoryHint: .isDirectory)
        storageURL = applicationSupportURL
            .appending(path: "repositories.json", directoryHint: .notDirectory)
        load()
    }

    func chooseRepositories() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Add Plan Repositories"
        panel.message = "Choose one or more repository roots. PlansBar reads them in place."
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return false }
        add(panel.urls)
        return true
    }

    func add(_ urls: [URL]) {
        var changed = false
        for selectedURL in urls {
            let url = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
            guard !repositories.contains(where: { $0.path == url.path }),
                  let bookmark = try? url.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                  )
            else { continue }
            repositories.append(RegisteredRepository(id: UUID(), path: url.path, bookmark: bookmark))
            changed = true
        }
        if changed {
            repositories.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            save()
        }
    }

    func remove(_ repository: RegisteredRepository) {
        repositories.removeAll { $0.id == repository.id }
        save()
    }

    func resolvedRepositories() -> [ResolvedRepository] {
        var updated = repositories
        var changed = false
        let roots = repositories.enumerated().map { index, repository in
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: repository.bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
                if stale || resolved.path != repository.path,
                   let bookmark = try? resolved.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                   ) {
                    updated[index] = RegisteredRepository(id: repository.id, path: resolved.path, bookmark: bookmark)
                    changed = true
                }
                return ResolvedRepository(registrationID: repository.id.uuidString, url: resolved)
            }
            return ResolvedRepository(
                registrationID: repository.id.uuidString,
                url: URL(fileURLWithPath: repository.path, isDirectory: true)
            )
        }
        if changed {
            repositories = updated
            save()
        }
        return roots
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode([RegisteredRepository].self, from: data)
        else { return }
        repositories = stored
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(repositories)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Не удалось сохранить список репозиториев PlansBar: %@", error.localizedDescription)
        }
    }
}
