import AppKit
import Combine
import Foundation

enum ConnectionState: Equatable {
    case starting
    case connected
    case unavailable(String)

    var label: String {
        switch self {
        case .starting: return "Starting index"
        case .connected: return "Index connected"
        case .unavailable: return "Source preview"
        }
    }
}

@MainActor
final class IndexClient: ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty
    @Published private(set) var connection: ConnectionState = .unavailable(
        "Workspace selection and local indexing arrive in the next implementation task."
    )
    @Published private(set) var isRefreshing = false

    func refresh() async {}

    func rescan() async {}

    func copyPrompt(_ task: PlanTask) async -> String {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.portablePrompt, forType: .string)
        return "Prompt copied"
    }
}
