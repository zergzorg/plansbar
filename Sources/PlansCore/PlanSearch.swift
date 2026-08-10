import Foundation

public enum PlanSearch {
    public static func rank(
        query: String,
        title: String,
        repository: String,
        nextStep: String?
    ) -> Int? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return 0 }

        let title = normalize(title)
        if title.hasPrefix(needle) { return 0 }
        if title.contains(needle) { return 1 }
        if normalize(repository).contains(needle) { return 2 }
        if normalize(nextStep ?? "").contains(needle) { return 3 }
        return nil
    }

    public static func lifecycleRank(_ bucket: String) -> Int {
        switch bucket {
        case "active": return 0
        case "backlog": return 1
        case "completed": return 2
        default: return 3
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
