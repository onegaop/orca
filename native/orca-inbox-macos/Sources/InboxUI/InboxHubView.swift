import SwiftUI
import AppKit
import InboxCore

public struct InboxHubView: View {
    public let state: InboxPanelState
    @Binding public var filter: InboxFeedFilter
    public let embeddedInNotch: Bool
    public let focusDispatchTrigger: Int
    public let onRefresh: () -> Void
    public let onSelectHost: (HostTarget) -> Void
    public let onArchiveAllDone: () -> Void
    public let onSetPresentationMode: (InboxPresentationMode) -> Void
    public let onSetNotificationsEnabled: (Bool) -> Void
    public let onDispatchTask: (String, String, String) async throws -> Void
    public let onCollapse: (() -> Void)?
    public let onQuit: () -> Void
    public let cardHandlers: InboxCardHandlers

    @State private var selectedWorktreeId = ""
    @State private var selectedAgentId = "codex"
    @State private var dispatchPrompt = ""
    @State private var isDispatching = false
    @State private var dispatchError: String?
    @State private var expandedRowID: String?
    @State private var replyingRowID: String?
    @State private var selectedRowID: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    public init(
        state: InboxPanelState,
        filter: Binding<InboxFeedFilter>,
        embeddedInNotch: Bool = false,
        focusDispatchTrigger: Int = 0,
        onRefresh: @escaping () -> Void,
        onSelectHost: @escaping (HostTarget) -> Void = { _ in },
        onArchiveAllDone: @escaping () -> Void = {},
        onSetPresentationMode: @escaping (InboxPresentationMode) -> Void = { _ in },
        onSetNotificationsEnabled: @escaping (Bool) -> Void = { _ in },
        onDispatchTask: @escaping (String, String, String) async throws -> Void = { _, _, _ in },
        onCollapse: (() -> Void)? = nil,
        onQuit: @escaping () -> Void,
        cardHandlers: InboxCardHandlers
    ) {
        self.state = state
        self._filter = filter
        self.embeddedInNotch = embeddedInNotch
        self.focusDispatchTrigger = focusDispatchTrigger
        self.onRefresh = onRefresh
        self.onSelectHost = onSelectHost
        self.onArchiveAllDone = onArchiveAllDone
        self.onSetPresentationMode = onSetPresentationMode
        self.onSetNotificationsEnabled = onSetNotificationsEnabled
        self.onDispatchTask = onDispatchTask
        self.onCollapse = onCollapse
        self.onQuit = onQuit
        self.cardHandlers = cardHandlers
    }

    private var counts: InboxTriageCounts {
        guard let snapshot = state.snapshot else { return .zero }
        return InboxTriageRules.counts(snapshot: snapshot, archivedTimestamps: state.archivedTimestamps)
    }

    private var visibleRows: [AgentRow] {
        guard let snapshot = state.snapshot else { return [] }
        return InboxTriageRules.filteredRows(
            snapshot: snapshot,
            filter: filter,
            archivedTimestamps: state.archivedTimestamps
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !embeddedInNotch {
                topHeader
                    .padding(.horizontal, InboxMetrics.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                Divider()
            }

            InboxQuickDispatchBar(
                workspaces: state.dispatchWorkspaces,
                agents: state.installedAgents,
                selectedWorktreeId: $selectedWorktreeId,
                selectedAgentId: $selectedAgentId,
                promptText: $dispatchPrompt,
                isDispatching: isDispatching,
                focusTrigger: focusDispatchTrigger,
                onDispatch: performDispatch
            )

            Divider()

            filterBar
                .padding(.horizontal, InboxMetrics.horizontalPadding)
                .padding(.vertical, 8)

            Divider()

            if let errorText = dispatchError ?? state.actionProblem {
                InlineNoticeBanner(
                    tone: .warning,
                    symbol: "exclamationmark.triangle",
                    title: "操作提示",
                    detail: errorText,
                    helpText: errorText,
                    actionTitle: "知道了",
                    actionDisabled: false,
                    action: { dispatchError = nil }
                )
                .padding(.horizontal, InboxMetrics.horizontalPadding)
                .padding(.top, 8)
            }

            ZStack(alignment: .bottom) {
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let toast = state.toastMessage {
                    Text(toast)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.black.opacity(0.82))
                        }
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: state.toastMessage)

            Divider()

            footer
                .padding(.horizontal, InboxMetrics.horizontalPadding)
                .frame(height: InboxMetrics.footerHeight)
        }
        .frame(width: InboxMetrics.hubWidth, height: InboxMetrics.hubHeight)
        .background {
            if reduceTransparency && !embeddedInNotch {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .onAppear(perform: syncDispatchDefaults)
        .onChange(of: state.defaultDispatchWorktreeId) { _, _ in syncDispatchDefaults() }
        .onChange(of: state.defaultDispatchAgent) { _, _ in syncDispatchDefaults() }
        .onChange(of: state.dispatchWorkspaces.count) { _, _ in syncDispatchDefaults() }
    }

    private var topHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Orca 指挥台")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                hostSubtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassEffectContainer(spacing: 8) {
                Button(action: onRefresh) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(state.refreshing ? 0 : 1)
                        if state.refreshing {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18, height: 18)
                }
                .inboxActionButtonStyle(reduceTransparency: reduceTransparency, isCircular: true)
                .disabled(state.refreshing)
                .help("立即同步")
            }
            .fixedSize()
        }
    }

    private var hostSubtitle: some View {
        HStack(spacing: 5) {
            if state.hosts.count > 1 {
                Menu {
                    ForEach(state.hosts) { host in
                        Button {
                            onSelectHost(host)
                        } label: {
                            HStack {
                                Label(host.displayName, systemImage: host.symbolName)
                                if host.id == state.selectedHost.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: state.selectedHost.symbolName)
                            .font(.system(size: 10))
                        Text(state.selectedHost.displayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.75)
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Label(state.selectedHost.displayName, systemImage: state.selectedHost.symbolName)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }

            if counts.blocked > 0 {
                Text("· \(counts.blocked) 项阻塞")
                    .foregroundStyle(InboxPalette.blockedInk(colorScheme: colorScheme))
                    .monospacedDigit()
            } else if counts.working > 0 {
                Text("· \(counts.working) 个运行中")
                    .foregroundStyle(InboxPalette.workingInk(colorScheme: colorScheme))
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(InboxFeedFilter.allCases) { item in
                let count = filterCount(for: item)
                let selected = filter == item
                Button {
                    filter = item
                } label: {
                    HStack(spacing: 4) {
                        Text(item.title)
                        if state.snapshot != nil {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background {
                                    Capsule()
                                        .fill(badgeFill(for: item, selected: selected))
                                }
                                .foregroundStyle(badgeForeground(for: item, selected: selected))
                        }
                    }
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background {
                        Capsule()
                            .fill(selected ? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            if filter == .inbox && counts.unreadDone > 0 {
                Button(action: onArchiveAllDone) {
                    Label("清空已完成", systemImage: "tray.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("将收件箱中所有已完成项标记为已读归档")
            }

            if embeddedInNotch {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(state.refreshing)
                .help("立即同步")

                if let onCollapse {
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("收起灵动岛 (Esc)")
                }
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if let snapshot = state.snapshot {
            VStack(spacing: 0) {
                if let problem = state.problem {
                    InlineNoticeBanner(
                        tone: .warning,
                        symbol: "bolt.horizontal.circle.fill",
                        title: "连接中断 · 当前显示缓存",
                        detail: problem,
                        helpText: problem,
                        actionTitle: state.refreshing ? "重试中" : "重试",
                        actionDisabled: state.refreshing,
                        action: onRefresh
                    )
                    .padding(.horizontal, InboxMetrics.horizontalPadding)
                    .padding(.top, 8)
                } else if snapshot.truncated {
                    InlineNoticeBanner(
                        tone: .info,
                        symbol: "info.circle",
                        title: "仅显示部分任务",
                        detail: "当前主机返回了截断后的会话列表。",
                        helpText: nil,
                        actionTitle: nil,
                        actionDisabled: false,
                        action: nil
                    )
                    .padding(.horizontal, InboxMetrics.horizontalPadding)
                    .padding(.top, 8)
                }

                let rows = visibleRows
                if rows.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(rows) { row in
                                InboxTaskCardView(
                                    row: row,
                                    environment: state.selectedHost.id,
                                    referenceNow: state.effectiveNow,
                                    isArchived: InboxTriageRules.isArchived(
                                        row,
                                        archivedTimestamps: state.archivedTimestamps
                                    ),
                                    isSelected: selectedRowID == row.id,
                                    isExpanded: expandedRowID == row.id,
                                    isReplying: replyingRowID == row.id,
                                    handlers: cardHandlers,
                                    onToggleExpand: {
                                        expandedRowID = expandedRowID == row.id ? nil : row.id
                                    },
                                    onToggleReply: {
                                        replyingRowID = replyingRowID == row.id ? nil : row.id
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, InboxMetrics.horizontalPadding)
                        .padding(.vertical, 10)
                    }
                    .defaultScrollAnchor(.top)
                }
            }
        } else if let problem = state.problem {
            CenteredStatusStateView(
                symbol: "bolt.horizontal.circle.fill",
                showsProgress: false,
                title: "暂时连不上 Orca",
                description: problem,
                footnote: "不会把断线误判为没有待办。",
                primaryActionTitle: state.refreshing ? "正在重新连接…" : "重新连接",
                primaryActionDisabled: state.refreshing,
                primaryAction: onRefresh
            )
        } else {
            CenteredStatusStateView(
                symbol: nil,
                showsProgress: true,
                title: "正在同步 Agent 状态",
                description: "通过本机 Orca 读取会话与最新摘要。",
                footnote: "展开每 3 秒刷新，收起后每 10 秒同步。",
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        }
    }

    private var emptyView: some View {
        switch filter {
        case .inbox:
            CenteredStatusStateView(
                symbol: "checkmark.seal",
                showsProgress: false,
                title: "收件箱已清空",
                description: "卡住等你拍板或刚刚跑完的 Agent 会自动出现在这里。",
                footnote: counts.working > 0 ? "后台仍有 \(counts.working) 个 Agent 正在运行" : nil,
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        case .working:
            CenteredStatusStateView(
                symbol: "waveform",
                showsProgress: false,
                title: "当前没有后台运行中的任务",
                description: "可以直接在顶部输入框一句话派发新任务。",
                footnote: nil,
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        case .all:
            CenteredStatusStateView(
                symbol: "tray",
                showsProgress: false,
                title: "还没有活跃会话",
                description: "在上方输入任务或打开 Orca 开始一个新对话。",
                footnote: nil,
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(state.problem == nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                if state.refreshing {
                    Text("同步中…")
                } else if let updated = state.updated {
                    Text("\(state.selectedHost.displayName) · \(updated.formatted(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                } else {
                    Text(state.selectedHost.displayName)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 6)

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        cardHandlers.onOpenOrca()
                    } label: {
                        Label("打开 Orca", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11.5))
                    }
                    .inboxActionButtonStyle(reduceTransparency: reduceTransparency)
                    .controlSize(.small)

                    Menu {
                        Section("显示形态") {
                            ForEach(InboxPresentationMode.allCases) { mode in
                                Button {
                                    onSetPresentationMode(mode)
                                } label: {
                                    HStack {
                                        Text(mode.title)
                                        if state.presentationMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        if state.hosts.count > 1 {
                            Section("切换主机") {
                                ForEach(state.hosts) { host in
                                    Button {
                                        onSelectHost(host)
                                    } label: {
                                        HStack {
                                            Label(host.displayName, systemImage: host.symbolName)
                                            if host.id == state.selectedHost.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        Toggle(
                            "阻塞/完成时系统轻提醒",
                            isOn: Binding(
                                get: { state.notificationsEnabled },
                                set: { onSetNotificationsEnabled($0) }
                            )
                        )

                        Divider()

                        Button("退出任务收件箱", action: onQuit)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.button)
                    .inboxActionButtonStyle(reduceTransparency: reduceTransparency, isCircular: true)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("更多设置")
                }
            }
            .fixedSize()
        }
    }

    private func filterCount(for item: InboxFeedFilter) -> Int {
        switch item {
        case .inbox: counts.inbox
        case .working: counts.working
        case .all: counts.total
        }
    }

    private func badgeFill(for item: InboxFeedFilter, selected: Bool) -> Color {
        if item == .inbox && counts.urgent > 0 {
            return InboxPalette.waitingInk(colorScheme: colorScheme).opacity(0.24)
        }
        if item == .inbox && counts.unreadDone > 0 {
            return InboxPalette.doneInk(colorScheme: colorScheme).opacity(0.22)
        }
        return Color.primary.opacity(selected ? 0.16 : 0.10)
    }

    private func badgeForeground(for item: InboxFeedFilter, selected: Bool) -> Color {
        if item == .inbox && counts.urgent > 0 {
            return InboxPalette.waitingInk(colorScheme: colorScheme)
        }
        if item == .inbox && counts.unreadDone > 0 {
            return InboxPalette.doneInk(colorScheme: colorScheme)
        }
        return selected ? .primary : .secondary
    }

    private func syncDispatchDefaults() {
        if selectedWorktreeId.isEmpty || !state.dispatchWorkspaces.contains(where: { $0.worktreeId == selectedWorktreeId }) {
            selectedWorktreeId = state.defaultDispatchWorktreeId ?? state.dispatchWorkspaces.first?.worktreeId ?? ""
        }
        if !state.installedAgents.contains(where: { $0.id == selectedAgentId }) {
            selectedAgentId = state.defaultDispatchAgent
        }
    }

    private func performDispatch() {
        let trimmed = dispatchPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedWorktreeId.isEmpty, !selectedAgentId.isEmpty, !isDispatching else { return }
        isDispatching = true
        dispatchError = nil
        let worktreeId = selectedWorktreeId
        let agentId = selectedAgentId
        Task {
            do {
                try await onDispatchTask(worktreeId, agentId, trimmed)
                await MainActor.run {
                    dispatchPrompt = ""
                    isDispatching = false
                    filter = .working
                }
            } catch {
                await MainActor.run {
                    dispatchError = error.localizedDescription
                    isDispatching = false
                }
            }
        }
    }
}
