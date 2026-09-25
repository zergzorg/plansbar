import SwiftUI
import PlansCore

struct MarketingPreviewView: View {
    let mode: String

    private var repositories: [Repository] {
        let bucket: PlanBucket = mode == "backlog" ? .backlog : .active
        return Snapshot.marketingPreview.repositories.compactMap { $0.filtered(to: bucket) }
    }

    private var tasks: [PlanTask] { repositories.flatMap(\.tasks) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                ForEach(repositories) { repository in
                    repositoryHeader(repository)
                    ForEach(repository.tasks) { task in
                        previewRow(task)
                        Divider().padding(.leading, 14).opacity(0.5)
                    }
                }
                Spacer(minLength: 0)
            }
            Divider()
            footer
        }
        .frame(width: PanelView.width, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Plans")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(tasks.count) plan\(tasks.count == 1 ? "" : "s") · \(tasks.filter(\.needsAttention).count) need attention")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(["rectangle.compress.vertical", "folder.badge.plus", "terminal", "line.3.horizontal.decrease.circle", "arrow.clockwise"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    modeTab("Focus", selected: mode != "backlog")
                    modeTab("Backlog", selected: mode == "backlog")
                }
                .padding(2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 132, height: 26)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                    Text("Search plans")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func modeTab(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: selected ? .semibold : .regular))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(selected ? .primary : .secondary)
            .background(selected ? Color.white.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func repositoryHeader(_ repository: Repository) -> some View {
        HStack {
            Text(repository.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(repository.tasks.count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
    }

    private func previewRow(_ task: PlanTask) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(signalColor(task.signal))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 6) {
                    Text(task.progressCountLabel)
                    progressBar(task)
                    Text("·")
                    Text(task.modifiedLabel)
                    if task.signal != .normal {
                        Text("·")
                        Text(task.signal.label)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let next = task.nextOpenStep {
                    Text(next)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func progressBar(_ task: PlanTask) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(task.progressPercent ?? 0) / 100)
            }
        }
        .frame(width: 52, height: 4)
    }

    private func signalColor(_ signal: PlanSignal) -> Color {
        switch signal {
        case .normal: return .accentColor
        case .ready: return .green
        case .stale, .noContext: return .orange
        case .blocked: return .red
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("Index connected")
            Spacer()
            Text("New Idea…")
            Text("v\(PlansBarVersion.current)")
            Text("Quit")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
