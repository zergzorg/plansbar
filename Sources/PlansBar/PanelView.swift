import SwiftUI

struct PanelView: View {
    static let width: CGFloat = 480

    @ObservedObject var client: IndexClient
    @ObservedObject var preferences: Preferences

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("compactMode") private var isCompact = false
    @State private var expandedTask: String?
    @State private var actionMessage = ""
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    private var searchTerm: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var repositories: [Repository] {
        client.snapshot.repositories
            .compactMap { repo in
                let tasks = repo.tasks.filter {
                    $0.isActive && matchesSearch($0, repository: repo.name)
                }
                guard !tasks.isEmpty, preferences.isVisible(repo.name) else { return nil }
                return Repository(name: repo.name, path: repo.path, tasks: tasks)
            }
            .sorted { $0.name < $1.name }
    }

    private var totalPlans: Int { repositories.reduce(0) { $0 + $1.tasks.count } }
    private var attentionCount: Int {
        repositories.reduce(0) { $0 + $1.tasks.filter(\.needsAttention).count }
    }
    private var repositoryChoices: [Repository] {
        client.snapshot.repositories
            .map { repo in
                Repository(name: repo.name, path: repo.path, tasks: repo.tasks.filter(\.isActive))
            }
            .filter { !$0.tasks.isEmpty }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content

            Divider()
            footer
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Plans in progress")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                summary

                Spacer(minLength: 4)

                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        isCompact.toggle()
                    }
                } label: {
                    Image(systemName: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isCompact ? Color.accentColor : Color.secondary)
                .accessibilityLabel(isCompact ? "Regular view" : "Compact view")
                .help(isCompact ? "Switch to regular view" : "Show more plans")

                Menu {
                    ForEach(repositoryChoices) { repo in
                        Toggle(isOn: Binding(
                            get: { preferences.isVisible(repo.name) },
                            set: { _ in preferences.toggle(repo.name) }
                        )) {
                            Text("\(repo.name) · \(repo.tasks.count)")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(repositoryChoices.isEmpty)
                .accessibilityLabel("Repository filter")
                .help("Choose repositories")

                Button {
                    Task { await client.rescan() }
                } label: {
                    if client.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(client.isRefreshing)
                .accessibilityLabel("Refresh index")
                .help("Refresh index")
            }

            searchField
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search plans", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isSearchFocused)
                .onExitCommand {
                    searchQuery = ""
                    isSearchFocused = false
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isSearchFocused ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                    lineWidth: isSearchFocused ? 1.5 : 1
                )
        }
    }

    @ViewBuilder
    private var summary: some View {
        if totalPlans > 0 || !searchTerm.isEmpty {
            HStack(spacing: 4) {
                Text("\(totalPlans) plan\(totalPlans == 1 ? "" : "s")")
                if attentionCount > 0 {
                    Text("·")
                    Text("\(attentionCount) need attention")
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        } else {
            Text(client.connection.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if repositories.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(repositories) { repo in
                        Section {
                            ForEach(repo.tasks.sorted(by: sortTasks)) { task in
                                PlanRowView(
                                    task: task,
                                    isExpanded: expandedTask == task.id,
                                    isCompact: isCompact,
                                    onToggle: {
                                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                            expandedTask = expandedTask == task.id ? nil : task.id
                                        }
                                    },
                                    onRun: { run(task) }
                                )
                                Divider()
                                    .padding(.leading, 14)
                                    .opacity(0.5)
                            }
                        } header: {
                            repoHeader(repo)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func repoHeader(_ repo: Repository) -> some View {
        HStack {
            Text(repo.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(repo.tasks.count)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 4 : 6)
        .background(.regularMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: emptyIcon)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(emptyTitle).font(.system(size: 12, weight: .medium))
            Text(emptyHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
    }

    private var emptyIcon: String {
        if !searchTerm.isEmpty { return "magnifyingglass" }
        if case .connected = client.connection { return "checkmark.circle" }
        return "antenna.radiowaves.left.and.right.slash"
    }

    private var emptyTitle: String {
        if !searchTerm.isEmpty { return "No plans found" }
        switch client.connection {
        case .connected: return "No active plans"
        case .starting: return "Starting index"
        case .unavailable: return "Source preview"
        }
    }

    private var emptyHint: String {
        if !searchTerm.isEmpty { return "Change the query or clear the search field." }
        switch client.connection {
        case .connected:
            return client.snapshot.repositories.isEmpty
                ? "The index is empty. Check that repositories contain docs/plans."
                : "The selected repositories have no active work."
        case .starting:
            return "The first scan may take up to a minute."
        case .unavailable(let reason):
            return reason
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if actionMessage.isEmpty {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                Text(client.connection.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(actionMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var connectionColor: Color {
        switch client.connection {
        case .connected: return .green
        case .starting: return .orange
        case .unavailable: return .red
        }
    }

    // MARK: - Actions

    private func run(_ task: PlanTask) {
        actionMessage = "Copying prompt for \(task.repo)…"
        Task {
            actionMessage = await client.copyPrompt(task)
            try? await Task.sleep(for: .seconds(4))
            actionMessage = ""
        }
    }

    private func matchesSearch(_ task: PlanTask, repository: String) -> Bool {
        searchTerm.isEmpty
            || task.title.localizedCaseInsensitiveContains(searchTerm)
            || repository.localizedCaseInsensitiveContains(searchTerm)
    }

    private func sortTasks(_ left: PlanTask, _ right: PlanTask) -> Bool {
        if left.isReadyToClose != right.isReadyToClose { return left.isReadyToClose }
        if left.needsAttention != right.needsAttention { return left.needsAttention }
        return (left.progressPercent ?? 0) > (right.progressPercent ?? 0)
    }
}
