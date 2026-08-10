import SwiftUI

struct NewIdeaEntryView: View {
    let repositories: [RegisteredRepository]
    let preferredAgent: AgentAdapter
    let onSubmit: (RegisteredRepository, String, AgentAdapter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var idea = ""
    @State private var repositoryID: UUID?

    init(
        repositories: [RegisteredRepository],
        preferredAgent: AgentAdapter,
        onSubmit: @escaping (RegisteredRepository, String, AgentAdapter) -> Void
    ) {
        self.repositories = repositories
        self.preferredAgent = preferredAgent
        self.onSubmit = onSubmit
        _repositoryID = State(initialValue: repositories.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New idea")
                .font(.headline)

            TextField("What should the plan accomplish?", text: $idea)
                .textFieldStyle(.roundedBorder)

            Picker("Repository", selection: $repositoryID) {
                ForEach(repositories) { repository in
                    Text(repository.name).tag(Optional(repository.id))
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if preferredAgent == .askEveryTime {
                    Menu("Create prompt") {
                        submitButton(.codex)
                        submitButton(.claude)
                        submitButton(.copyOnly)
                    }
                } else {
                    Button(preferredAgent == .copyOnly ? "Copy prompt" : "Open \(preferredAgent.title)") {
                        submit(preferredAgent)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var canSubmit: Bool {
        repositoryID != nil && !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitButton(_ adapter: AgentAdapter) -> some View {
        Button(adapter == .copyOnly ? "Copy prompt" : adapter.title) {
            submit(adapter)
        }
        .disabled(!canSubmit)
    }

    private func submit(_ adapter: AgentAdapter) {
        guard let repository = repositories.first(where: { $0.id == repositoryID }) else { return }
        onSubmit(repository, idea.trimmingCharacters(in: .whitespacesAndNewlines), adapter)
        dismiss()
    }
}
