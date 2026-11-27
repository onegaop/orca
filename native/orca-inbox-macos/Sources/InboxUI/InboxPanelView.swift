import SwiftUI
import AppKit
import InboxCore

public struct InboxPanelView: View {
    public let state: InboxPanelState
    @Binding public var bucket: Bucket
    public let onRefresh: () -> Void
    public let onSelectHost: (HostTarget) -> Void
    public let onOpenOrca: () -> Void
    public let onCopySessionID: (String) -> Void
    public let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    public init(
        state: InboxPanelState,
        bucket: Binding<Bucket>,
        onRefresh: @escaping () -> Void,
        onSelectHost: @escaping (HostTarget) -> Void = { _ in },
        onOpenOrca: @escaping () -> Void,
        onCopySessionID: @escaping (String) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.state = state
        self._bucket = bucket
        self.onRefresh = onRefresh
        self.onSelectHost = onSelectHost
        self.onOpenOrca = onOpenOrca
        self.onCopySessionID = onCopySessionID
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, InboxMetrics.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 10)

            switcher
                .padding(.horizontal, InboxMetrics.horizontalPadding)
                .padding(.bottom, 10)

            Divider()

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
                .padding(.horizontal, InboxMetrics.horizontalPadding)
                .frame(height: InboxMetrics.footerHeight)
        }
        .frame(width: InboxMetrics.panelWidth, height: InboxMetrics.panelHeight)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    // MARK: - Top Navigation Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("任务收件箱")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                headerSubtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            GlassEffectContainer(spacing: 8) {
                Button(action: onRefresh) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(state.refreshing ? 0 : 1)
                        if state.refreshing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 18, height: 18)
                }
                .inboxActionButtonStyle(reduceTransparency: reduceTransparency, isCircular: true)
                .disabled(state.refreshing)
                .help("刷新任务状态")
                .accessibilityLabel(state.refreshing ? "正在刷新" : "刷新")
            }
            .fixedSize()
            .layoutPriority(1)
        }
    }

    private var headerSubtitle: some View {
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
                            .font(.system(size: 10.5))
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
                .help("切换 Orca 主机")
            } else {
                Label("Orca · \(state.selectedHost.displayName)", systemImage: state.selectedHost.symbolName)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }

            if state.refreshing {
                Text("· 正在刷新")
                    .foregroundStyle(.secondary)
            } else if state.problem != nil {
                HStack(spacing: 3) {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                    Text("连接中断")
                }
                .foregroundStyle(InboxPalette.waitingInk(colorScheme: colorScheme))
            } else if let blocked = state.snapshot?.blockedCount, blocked > 0 {
                HStack(spacing: 3) {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 9.5))
                    Text("\(blocked) 项阻塞")
                        .monospacedDigit()
                }
                .foregroundStyle(InboxPalette.blockedInk(colorScheme: colorScheme))
            }
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var switcher: some View {
        Picker("任务状态", selection: $bucket) {
            ForEach(Bucket.allCases) { item in
                let count = state.snapshot?.count(in: item)
                Text(count.map { "\(item.title) \($0)" } ?? item.title)
                    .monospacedDigit()
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content Area (Flat Content Layer, No Glass Cards)

    @ViewBuilder
    private var contentArea: some View {
        if let snapshot = state.snapshot {
            VStack(spacing: 0) {
                if let problem = state.problem {
                    InlineNoticeBanner(
                        tone: .warning,
                        symbol: "bolt.horizontal.circle.fill",
                        title: "连接中断 · 当前显示旧数据",
                        detail: staleDetailText,
                        helpText: problem,
                        actionTitle: state.refreshing ? "重试中" : "重试",
                        actionDisabled: state.refreshing,
                        action: onRefresh
                    )
                    .padding(.horizontal, InboxMetrics.horizontalPadding)
                    .padding(.top, 10)
                } else if snapshot.truncated {
                    InlineNoticeBanner(
                        tone: .info,
                        symbol: "info.circle",
                        title: "仅显示部分任务",
                        detail: "本机 Orca 返回了截断后的会话列表。",
                        helpText: nil,
                        actionTitle: nil,
                        actionDisabled: false,
                        action: nil
                    )
                    .padding(.horizontal, InboxMetrics.horizontalPadding)
                    .padding(.top, 10)
                }

                let projects = snapshot.projects(in: bucket)
                if projects.isEmpty {
                    emptyBucketView(snapshot: snapshot)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                                if index > 0 {
                                    Divider()
                                        .padding(.vertical, 12)
                                }
                                ProjectSectionView(
                                    project: project,
                                    bucket: bucket,
                                    referenceNow: state.effectiveNow,
                                    onCopySessionID: onCopySessionID,
                                    onOpenOrca: onOpenOrca
                                )
                            }
                        }
                        .padding(.horizontal, InboxMetrics.horizontalPadding)
                        .padding(.vertical, 12)
                    }
                    .defaultScrollAnchor(.top)
                    .id(bucket)
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
                title: "正在读取任务",
                description: "通过本机 Orca 读取当前会话状态。",
                footnote: "仅在打开收件箱时刷新。",
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        }
    }

    private func emptyBucketView(snapshot: Snapshot) -> some View {
        let otherSummary = otherBucketsSummary(snapshot: snapshot)
        switch bucket {
        case .attention:
            return CenteredStatusStateView(
                symbol: "checkmark.circle",
                showsProgress: false,
                title: "暂时不用你出手",
                description: "阻塞或等待输入的 Agent 会优先出现在这里。",
                footnote: otherSummary,
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        case .working:
            return CenteredStatusStateView(
                symbol: "waveform",
                showsProgress: false,
                title: "没有进行中的任务",
                description: "正在执行的 Agent 会显示在这里。",
                footnote: otherSummary,
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        case .done:
            return CenteredStatusStateView(
                symbol: "checkmark.circle",
                showsProgress: false,
                title: "没有已完成的任务",
                description: "本机 Orca 已报告完成的会话会显示在这里。",
                footnote: otherSummary,
                primaryActionTitle: nil,
                primaryActionDisabled: false,
                primaryAction: nil
            )
        }
    }

    private func otherBucketsSummary(snapshot: Snapshot) -> String? {
        let parts = Bucket.allCases.compactMap { other -> String? in
            guard other != bucket else { return nil }
            let count = snapshot.count(in: other)
            guard count > 0 else { return nil }
            return "\(other.title) \(count)"
        }
        guard !parts.isEmpty else { return nil }
        return "其他分组：" + parts.joined(separator: " · ")
    }

    private var staleDetailText: String {
        if let updated = state.updated {
            return "上次成功同步于 \(updated.formatted(date: .omitted, time: .shortened))，确认 Orca 运行后重试。"
        }
        return "确认 \(state.selectedHost.displayName) 的 Orca 运行后点击重试。"
    }

    // MARK: - Footer (Liquid Glass Action Controls)

    private var footer: some View {
        HStack(spacing: 10) {
            footerStatus
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onOpenOrca) {
                        Label("打开 Orca", systemImage: "arrow.up.forward.app")
                    }
                    .inboxActionButtonStyle(reduceTransparency: reduceTransparency)
                    .controlSize(.regular)

                    Menu {
                        Button("退出任务收件箱", action: onQuit)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.button)
                    .inboxActionButtonStyle(reduceTransparency: reduceTransparency, isCircular: true)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("更多操作")
                }
            }
            .fixedSize()
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        if state.refreshing {
            HStack(spacing: 5) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 10.5))
                Text("正在同步状态…")
            }
            .foregroundStyle(.secondary)
        } else if let problem = state.problem {
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 10.5))
                Text(state.snapshot == nil ? "未连接" : "旧数据 · 连接中断")
            }
            .foregroundStyle(InboxPalette.waitingInk(colorScheme: colorScheme))
            .help(problem)
        } else if let time = state.updated {
            Text("更新于 \(time.formatted(date: .omitted, time: .shortened))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("\(state.selectedHost.displayName) · 只读")
                .foregroundStyle(.secondary)
        }
    }
}
