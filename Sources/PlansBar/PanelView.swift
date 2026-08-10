import SwiftUI
import PlansCore

struct PanelView: View {
    static let width: CGFloat = 480

    @ObservedObject var client: IndexClient
    @ObservedObject var preferences: Preferences
    @ObservedObject var agentPreferences: AgentPreferences
    @ObservedObject var accessStore: RepositoryAccessStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("compactMode") private var isCompact = false
    @State private var expandedTask: String?
    @State private var actionMessage = ""
    @State private var searchQuery = ""
    @State private var selectedSearchResult: String?
    @FocusState private var isSearchFocused: Bool

    private var searchTerm: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var repositories: [Repository] {
        client.snapshot.repositories
            .compactMap { repo in
                let tasks = repo.tasks.filter(\.isActive)
                guard !tasks.isEmpty else { return nil }
                guard preferences.isVisible(repo.id) else { return nil }
                return Repository(
                    identity: repo.identity,
                    name: repo.name,
                    path: repo.path,
                    tasks: tasks
                )
            }
            .sorted { $0.name < $1.name }
    }

    private var searchResults: [PlanTask] {
        guard !searchTerm.isEmpty else { return [] }
        return client.snapshot.repositories
            .flatMap(\.tasks)
            .filter { searchRank($0) != nil }
            .sorted(by: sortTasks)
    }

    private var visibleTasks: [PlanTask] {
        searchTerm.isEmpty ? repositories.flatMap(\.tasks) : searchResults
    }

    private var totalPlans: Int { visibleTasks.count }
    private var attentionCount: Int {
        visibleTasks.filter(\.needsAttention).count
    }
    private var repositoryChoices: [Repository] {
        client.snapshot.repositories
            .map { repo in
                Repository(
                    identity: repo.identity,
                    name: repo.name,
                    path: repo.path,
                    tasks: repo.tasks.filter(\.isActive)
                )
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
        .onReceive(NotificationCenter.default.publisher(for: .focusPlansSearch)) { _ in
            isSearchFocused = true
        }
        .onChange(of: searchQuery) {
            selectedSearchResult = searchResults.first?.id
        }
        .onKeyPress(.downArrow) { moveSearchSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSearchSelection(by: -1) }
        .onKeyPress(.return) { openSelectedSearchResult() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Plans")
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
                    Button("Add Repository…", action: addRepositories)
                    if !accessStore.repositories.isEmpty {
                        Divider()
                        Menu("Remove Repository") {
                            ForEach(accessStore.repositories) { repository in
                                Button(repository.path, role: .destructive) {
                                    accessStore.remove(repository)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Manage repositories")
                .help("Add or remove repositories")

                Menu {
                    Picker("Preferred agent", selection: $agentPreferences.preferred) {
                        ForEach(AgentAdapter.allCases) { adapter in
                            Text(adapter.title).tag(adapter)
                        }
                    }
                } label: {
                    Image(systemName: "terminal")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Preferred agent: \(agentPreferences.preferred.title)")
                .help("Choose the default agent")

                Menu {
                    ForEach(repositoryChoices) { repo in
                        Toggle(isOn: Binding(
                            get: { preferences.isVisible(repo.id) },
                            set: { _ in preferences.toggle(repo.id) }
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
                .accessibilityLabel("Search plans by title, repository, or next step")
                .accessibilityValue("\(searchResults.count) results")
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
        if !searchTerm.isEmpty {
            if searchResults.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults) { task in
                            planRow(task, showsContext: true)
                        }
                    }
                }
            }
        } else if repositories.isEmpty && client.repositoryIssues.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(client.repositoryIssues) { issue in
                        repositoryIssue(issue)
                        Divider().padding(.leading, 14).opacity(0.5)
                    }

                    ForEach(repositories) { repo in
                        Section {
                            ForEach(repo.tasks.sorted(by: sortTasks)) { task in
                                planRow(task)
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

    private func planRow(_ task: PlanTask, showsContext: Bool = false) -> some View {
        VStack(spacing: 0) {
            PlanRowView(
                task: task,
                isExpanded: expandedTask == task.id,
                isCompact: isCompact,
                showsContext: showsContext,
                isSelected: showsContext && selectedSearchResult == task.id,
                preferredAgent: agentPreferences.preferred,
                onToggle: {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        if showsContext { selectedSearchResult = task.id }
                        expandedTask = expandedTask == task.id ? nil : task.id
                    }
                },
                onRun: { adapter in run(task, with: adapter) }
            )
            Divider()
                .padding(.leading, 14)
                .opacity(0.5)
        }
    }

    private func repositoryIssue(_ issue: RepositoryIssue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: issue.state == .inaccessible ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                    .foregroundStyle(.orange)
                Text(issue.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(issue.state.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(issueDescription(issue))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if issue.preparationPrompt != nil {
                    Button("Copy preparation prompt") {
                        actionMessage = client.copyPreparationPrompt(issue)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Menu("Open with agent") {
                        Button("Codex CLI") { runPreparation(issue, with: .codex) }
                        Button("Claude Code CLI") { runPreparation(issue, with: .claude) }
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                }

                Button("Remove") {
                    removeRepository(path: issue.path)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func issueDescription(_ issue: RepositoryIssue) -> String {
        switch issue.state {
        case .missingStructure:
            return "Missing \(issue.missingPaths.joined(separator: ", ")). PlansBar will not create files itself."
        case .invalidPlans:
            return "\(issue.invalidPlanCount) plan candidate\(issue.invalidPlanCount == 1 ? "" : "s") must be converted to Plan Format v1."
        case .inaccessible:
            return "The repository cannot be read. Re-add it or check its location and permissions."
        case .ready:
            return "Repository is ready."
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

            if accessStore.repositories.isEmpty && searchTerm.isEmpty {
                Button("Add Repository…", action: addRepositories)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
    }

    private var emptyIcon: String {
        if !searchTerm.isEmpty { return "magnifyingglass" }
        if accessStore.repositories.isEmpty { return "folder.badge.plus" }
        if case .connected = client.connection { return "checkmark.circle" }
        return "exclamationmark.triangle"
    }

    private var emptyTitle: String {
        if !searchTerm.isEmpty { return "No plans found" }
        switch client.connection {
        case .connected: return "No active plans"
        case .starting: return "Starting index"
        case .unavailable: return accessStore.repositories.isEmpty ? "Add a repository" : "Repositories unavailable"
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

            Menu {
                Text("PlansBar \(AppInfo.versionLabel)")
                Button("Check Releases") {
                    NSWorkspace.shared.open(AppInfo.releasesURL)
                }
            } label: {
                Text("v\(AppInfo.versionLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("PlansBar version \(AppInfo.versionLabel)")

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

    private func addRepositories() {
        _ = accessStore.chooseRepositories()
    }

    private func removeRepository(path: String) {
        guard let repository = accessStore.repositories.first(where: { $0.path == path }) else { return }
        accessStore.remove(repository)
    }

    private func run(_ task: PlanTask, with adapter: AgentAdapter) {
        actionMessage = adapter == .copyOnly
            ? "Copying prompt for \(task.repo)…"
            : "Opening \(adapter.title)…"
        Task {
            actionMessage = await client.perform(task, with: adapter)
            try? await Task.sleep(for: .seconds(4))
            actionMessage = ""
        }
    }

    private func runPreparation(_ issue: RepositoryIssue, with adapter: AgentAdapter) {
        actionMessage = "Opening \(adapter.title)…"
        Task {
            actionMessage = await client.performPreparation(issue, with: adapter)
            try? await Task.sleep(for: .seconds(4))
            actionMessage = ""
        }
    }

    private func searchRank(_ task: PlanTask) -> Int? {
        PlanSearch.rank(
            query: searchTerm,
            title: task.title,
            repository: task.repo,
            nextStep: task.nextOpenStep
        )
    }

    private func moveSearchSelection(by offset: Int) -> KeyPress.Result {
        guard !searchResults.isEmpty else { return .ignored }
        guard let current = searchResults.firstIndex(where: { $0.id == selectedSearchResult }) else {
            selectedSearchResult = searchResults[0].id
            return .handled
        }
        let next = min(max(current + offset, 0), searchResults.count - 1)
        selectedSearchResult = searchResults[next].id
        return .handled
    }

    private func openSelectedSearchResult() -> KeyPress.Result {
        guard !searchTerm.isEmpty, let selectedSearchResult else { return .ignored }
        expandedTask = selectedSearchResult
        isSearchFocused = false
        return .handled
    }

    private func sortTasks(_ left: PlanTask, _ right: PlanTask) -> Bool {
        if !searchTerm.isEmpty {
            let leftRank = searchRank(left) ?? Int.max
            let rightRank = searchRank(right) ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            let leftLifecycle = PlanSearch.lifecycleRank(left.bucket)
            let rightLifecycle = PlanSearch.lifecycleRank(right.bucket)
            if leftLifecycle != rightLifecycle { return leftLifecycle < rightLifecycle }
        }
        if left.isReadyToClose != right.isReadyToClose { return left.isReadyToClose }
        if left.needsAttention != right.needsAttention { return left.needsAttention }
        if left.progressPercent != right.progressPercent {
            return (left.progressPercent ?? 0) > (right.progressPercent ?? 0)
        }
        return left.id < right.id
    }
}
