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

    func isVisible(_ repository: String) -> Bool {
        !hidden.contains(repository)
    }

    func toggle(_ repository: String) {
        if hidden.contains(repository) {
            hidden.remove(repository)
        } else {
            hidden.insert(repository)
        }
        UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
    }
}
