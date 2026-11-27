import SwiftUI
import AppKit
import InboxCore

struct ProjectSectionView: View {
    let project: Project
    let bucket: Bucket
    let referenceNow: Date
    let onCopySessionID: (String) -> Void
    let onOpenOrca: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            projectHeader
            VStack(alignment: .leading, spacing: 10) {
                ForEach(project.workspaces) { workspace in
                    WorkspaceGroupView(
                        workspace: workspace,
                        referenceNow: referenceNow,
                        onCopySessionID: onCopySessionID,
                        onOpenOrca: onOpenOrca
                    )
                }
            }
            .overlay(alignment: .leading) {
                // Continuous hierarchy rail binding all workspaces under this project.
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(reduceTransparency ? 0.9 : 0.45))
                    .frame(width: 1)
                    .padding(.leading, InboxMetrics.projectIconWidth / 2)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var projectHeader: some View {
        HStack(alignment: .center, spacing: InboxMetrics.projectIconGap) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: InboxMetrics.projectIconWidth, alignment: .center)
                .accessibilityHidden(true)

            Text(project.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Spacer(minLength: 8)

            projectSummary
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .help(project.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var projectSummary: some View {
        if bucket == .attention, project.blockedCount > 0 {
            HStack(spacing: 5) {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("\(project.blockedCount) 阻塞")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(InboxPalette.blockedInk(colorScheme: colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: InboxMetrics.statusBadgeCornerRadius, style: .continuous)
                        .fill(reduceTransparency
                              ? Color(nsColor: .controlBackgroundColor)
                              : InboxPalette.blockedInk(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.11))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: InboxMetrics.statusBadgeCornerRadius, style: .continuous)
                        .strokeBorder(
                            InboxPalette.blockedInk(colorScheme: colorScheme).opacity(reduceTransparency ? 0.85 : 0.35),
                            lineWidth: reduceTransparency ? 1.2 : 0.75
                        )
                }

                if project.waitingCount > 0 {
                    Text("\(project.totalCount) 项")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("\(project.totalCount) 项")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct WorkspaceGroupView: View {
    let workspace: Workspace
    let referenceNow: Date
    let onCopySessionID: (String) -> Void
    let onOpenOrca: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: InboxMetrics.workspaceIconGap) {
                Image(systemName: "square.stack")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: InboxMetrics.workspaceIconWidth, alignment: .center)
                    .accessibilityHidden(true)

                Text(workspace.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(0)

                Spacer(minLength: 8)
            }
            .padding(.leading, InboxMetrics.workspaceIndent)
            .help(workspace.title)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(workspace.rows) { row in
                    AgentTaskRowView(
                        row: row,
                        referenceNow: referenceNow,
                        onCopySessionID: onCopySessionID,
                        onOpenOrca: onOpenOrca
                    )
                }
            }
        }
    }
}

struct AgentTaskRowView: View {
    let row: AgentRow
    let referenceNow: Date
    let onCopySessionID: (String) -> Void
    let onOpenOrca: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    private var isBlocked: Bool { row.stateKind == .blocked }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Leading status icon aligned on the unified row rail.
            Image(systemName: row.stateKind.symbolName)
                .font(.system(size: 13, weight: isBlocked ? .semibold : .medium))
                .foregroundStyle(InboxPalette.iconColor(for: row.stateKind, colorScheme: colorScheme))
                .frame(width: InboxMetrics.rowIconWidth, alignment: .center)
                .padding(.trailing, InboxMetrics.rowIconGap)
                .accessibilityHidden(true)

            // Primary title + optional agent name (never duplicated).
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: 13, weight: isBlocked ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let agent = row.subtitleAgent {
                    Text(agent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            Spacer(minLength: 8)

            // Fixed-alignment trailing status badge (never crowded out by long titles).
            StatusBadgeView(kind: row.stateKind)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .padding(.trailing, InboxMetrics.trailingColumnGap)

            // Fixed-width right-aligned relative time column.
            Text(CompactRelativeTime.string(updatedAtMs: row.updatedAt, relativeTo: referenceNow))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: InboxMetrics.timeColumnWidth, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.leading, InboxMetrics.rowIndent)
        .padding(.vertical, 6)
        .frame(minHeight: 38)
        .overlay(alignment: .leading) {
            if isBlocked {
                // Structural urgency rail for blocked items — no glass card, no clickable affordance.
                Capsule()
                    .fill(InboxPalette.blockedFill(colorScheme: colorScheme))
                    .frame(width: 3, height: 24)
                    .padding(.leading, InboxMetrics.rowIndent - 8)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .help(tooltipText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .contextMenu {
            if let id = row.orcaSessionId {
                Button("复制 Orca 会话 ID") {
                    onCopySessionID(id)
                }
            }
            Button("打开 Orca") {
                onOpenOrca()
            }
        }
    }

    private var tooltipText: String {
        var parts = [row.label, "状态：\(row.stateLabel)"]
        if let agent = row.subtitleAgent {
            parts.append("Agent：\(agent)")
        }
        if row.orcaSessionId != nil {
            parts.append("右键可复制会话 ID")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        let time = CompactRelativeTime.string(updatedAtMs: row.updatedAt, relativeTo: referenceNow)
        let parts = [row.stateLabel, row.label, row.subtitleAgent, time == "—" ? nil : time].compactMap { $0 }
        return parts.joined(separator: "，")
    }
}

struct StatusBadgeView: View {
    let kind: AgentStateKind

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    var body: some View {
        Text(kind.label)
            .font(.system(size: 10.5, weight: kind == .blocked ? .semibold : .medium))
            .foregroundStyle(foregroundColor)
            .frame(minWidth: InboxMetrics.statusBadgeMinWidth - 14)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background {
                RoundedRectangle(cornerRadius: InboxMetrics.statusBadgeCornerRadius, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: InboxMetrics.statusBadgeCornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
    }

    private var foregroundColor: Color {
        switch kind {
        case .blocked:
            return .white
        case .waiting:
            return InboxPalette.waitingInk(colorScheme: colorScheme)
        case .working:
            return InboxPalette.workingInk(colorScheme: colorScheme)
        case .done:
            return InboxPalette.doneInk(colorScheme: colorScheme)
        case .unknown:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .blocked:
            return InboxPalette.blockedFill(colorScheme: colorScheme)
        case .waiting:
            if reduceTransparency {
                return Color(nsColor: .controlBackgroundColor)
            }
            return InboxPalette.waitingInk(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.10)
        case .working:
            if reduceTransparency {
                return Color(nsColor: .controlBackgroundColor)
            }
            return InboxPalette.workingInk(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.08)
        case .done:
            if reduceTransparency {
                return Color(nsColor: .controlBackgroundColor)
            }
            return InboxPalette.doneInk(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.08)
        case .unknown:
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .blocked:
            return reduceTransparency ? Color.primary.opacity(0.35) : Color.clear
        case .waiting:
            return InboxPalette.waitingInk(colorScheme: colorScheme).opacity(reduceTransparency ? 0.85 : 0.45)
        case .working:
            return InboxPalette.workingInk(colorScheme: colorScheme).opacity(reduceTransparency ? 0.75 : 0.30)
        case .done:
            return InboxPalette.doneInk(colorScheme: colorScheme).opacity(reduceTransparency ? 0.75 : 0.30)
        case .unknown:
            return Color(nsColor: .separatorColor)
        }
    }

    private var borderWidth: CGFloat {
        switch kind {
        case .blocked:
            return reduceTransparency ? 1 : 0
        default:
            return reduceTransparency ? 1.2 : 0.85
        }
    }
}

struct InlineNoticeBanner: View {
    enum Tone {
        case warning
        case info
    }

    let tone: Tone
    let symbol: String
    let title: String
    let detail: String?
    let helpText: String?
    let actionTitle: String?
    let actionDisabled: Bool
    let action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(actionDisabled)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(surfaceFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(surfaceBorder, lineWidth: reduceTransparency ? 1.25 : 0.85)
        }
        .help(helpText ?? title)
    }

    private var accentColor: Color {
        switch tone {
        case .warning: InboxPalette.waitingInk(colorScheme: colorScheme)
        case .info: .secondary
        }
    }

    private var surfaceFill: Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        switch tone {
        case .warning:
            return Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.11)
        case .info:
            return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045)
        }
    }

    private var surfaceBorder: Color {
        switch tone {
        case .warning:
            return InboxPalette.waitingInk(colorScheme: colorScheme).opacity(reduceTransparency ? 0.85 : 0.35)
        case .info:
            return Color(nsColor: .separatorColor).opacity(reduceTransparency ? 0.95 : 0.5)
        }
    }
}

struct CenteredStatusStateView: View {
    let symbol: String?
    let showsProgress: Bool
    let title: String
    let description: String
    let footnote: String?
    let primaryActionTitle: String?
    let primaryActionDisabled: Bool
    let primaryAction: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: 28, height: 28)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            if let primaryActionTitle, let primaryAction {
                GlassEffectContainer(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .inboxActionButtonStyle(reduceTransparency: reduceTransparency)
                        .controlSize(.regular)
                        .disabled(primaryActionDisabled)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
