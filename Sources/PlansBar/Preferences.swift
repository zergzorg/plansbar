import Foundation

/// Какие репозитории показывать в панели. По умолчанию — все,
/// скрытые перечисляются явно, чтобы новый репозиторий сразу был виден.
@MainActor
final class Preferences: ObservableObject {
    private static let hiddenKey = "hiddenRepositories"

    @Published private(set) var hidden: Set<String>

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        hidden = Set(stored)
    }

    func isVisible(_ repositoryID: String) -> Bool {
        !hidden.contains(repositoryID)
    }

    func toggle(_ repositoryID: String) {
        if hidden.contains(repositoryID) {
            hidden.remove(repositoryID)
        } else {
            hidden.insert(repositoryID)
        }
        UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
    }
}
