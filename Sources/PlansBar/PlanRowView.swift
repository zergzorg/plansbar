import SwiftUI

struct PlanRowView: View {
    let task: PlanTask
    let isExpanded: Bool
    let isCompact: Bool
    let onToggle: () -> Void
    let onRun: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var copied: CopyKind?

    private enum CopyKind {
        case prompt, path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(signalColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, isCompact ? 4 : 5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? 3 : 1)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if !isCompact {
                            metadata(includePercentage: false)
                        }
                    }

                    Spacer(minLength: 4)

                    if isCompact {
                        Text(task.progressCountLabel)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isHovered || isExpanded ? .secondary : .tertiary)
                        .padding(.top, isCompact ? 3 : 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpanded ? "Hide next step" : "Show next step")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if isCompact {
                        metadata(includePercentage: true)
                    }

                    Text("Next step")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    Text(stepText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button(task.actionTitle, action: onRun)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!task.isMarkdown)

                        Menu {
                            Button {
                                copy(task.portablePrompt, kind: .prompt)
                            } label: {
                                Label("Copy prompt", systemImage: "doc.on.doc")
                            }

                            Button {
                                copy(task.planPath, kind: .path)
                            } label: {
                                Label("Copy path", systemImage: "link")
                            }

                            Divider()

                            Button {
                                NSWorkspace.shared.selectFile(task.planPath, inFileViewerRootedAtPath: "")
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                        } label: {
                            Label(copied == nil ? "More" : "Copied", systemImage: copied == nil ? "ellipsis.circle" : "checkmark")
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityLabel("More actions")

                        Spacer()
                    }
                }
                .padding(.leading, 15)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 5 : 9)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.035) : .clear)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }

    private func copy(_ text: String, kind: CopyKind) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = kind
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copied == kind { copied = nil }
        }
    }

    private func metadata(includePercentage: Bool) -> some View {
        HStack(spacing: 6) {
            Text(includePercentage ? task.progressLabel : task.progressCountLabel)
                .monospacedDigit()

            if task.checkboxTotal > 0 {
                ProgressView(value: Double(task.checkboxDone), total: Double(task.checkboxTotal))
                    .progressViewStyle(.linear)
                    .frame(width: isCompact ? 44 : 52)
                    .accessibilityHidden(true)
            }

            Text("·")
            Text(task.modifiedLabel)
            if task.signal != .normal {
                Text("·")
                Text(task.signal.label)
            }
        }
        .font(.system(size: isCompact ? 10 : 11))
        .foregroundStyle(.secondary)
    }

    private var stepText: AttributedString {
        let raw = task.nextOpenStep.flatMap { $0.isEmpty ? nil : $0 }
            ?? (task.isReadyToClose
                ? "All steps are complete. Review the result and close the plan."
                : "No open steps.")
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    private var accessibilityValue: String {
        var parts = [task.progressLabel, task.modifiedLabel]
        if task.signal != .normal { parts.append(task.signal.label) }
        parts.append(isExpanded ? "expanded" : "collapsed")
        return parts.joined(separator: ", ")
    }

    private var signalColor: Color {
        switch task.signal {
        case .normal: return .accentColor
        case .ready: return .green
        case .stale: return .orange
        case .noContext: return .orange
        case .blocked: return .red
        }
    }
}

extension PlanSignal: Equatable {}
