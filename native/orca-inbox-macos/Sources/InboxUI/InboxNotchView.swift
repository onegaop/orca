import SwiftUI
import InboxCore

public struct NotchHUDMetrics {
    public static let compactWidthWithNotch: CGFloat = 336
    public static let compactWidthFloating: CGFloat = 248
    public static let compactHeight: CGFloat = 34
    public static let expandedWidth: CGFloat = InboxMetrics.hubWidth
    public static let expandedTopBarHeight: CGFloat = 34
    public static let expandedTotalHeight: CGFloat = InboxMetrics.hubHeight + expandedTopBarHeight
}

public struct InboxNotchView: View {
    public let state: InboxPanelState
    @Binding public var filter: InboxFeedFilter
    public let hasPhysicalNotch: Bool
    public let isExpanded: Bool
    public let focusDispatchTrigger: Int
    public let onHoverChange: (Bool) -> Void
    public let onToggleExpand: () -> Void
    public let onCollapse: () -> Void
    public let onRefresh: () -> Void
    public let onSelectHost: (HostTarget) -> Void
    public let onArchiveAllDone: () -> Void
    public let onSetPresentationMode: (InboxPresentationMode) -> Void
    public let onSetNotificationsEnabled: (Bool) -> Void
    public let onDispatchTask: (String, String, String) async throws -> Void
    public let onQuit: () -> Void
    public let cardHandlers: InboxCardHandlers

    @State private var pulse = false

    public init(
        state: InboxPanelState,
        filter: Binding<InboxFeedFilter>,
        hasPhysicalNotch: Bool,
        isExpanded: Bool,
        focusDispatchTrigger: Int,
        onHoverChange: @escaping (Bool) -> Void,
        onToggleExpand: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSelectHost: @escaping (HostTarget) -> Void,
        onArchiveAllDone: @escaping () -> Void,
        onSetPresentationMode: @escaping (InboxPresentationMode) -> Void,
        onSetNotificationsEnabled: @escaping (Bool) -> Void,
        onDispatchTask: @escaping (String, String, String) async throws -> Void,
        onQuit: @escaping () -> Void,
        cardHandlers: InboxCardHandlers
    ) {
        self.state = state
        self._filter = filter
        self.hasPhysicalNotch = hasPhysicalNotch
        self.isExpanded = isExpanded
        self.focusDispatchTrigger = focusDispatchTrigger
        self.onHoverChange = onHoverChange
        self.onToggleExpand = onToggleExpand
        self.onCollapse = onCollapse
        self.onRefresh = onRefresh
        self.onSelectHost = onSelectHost
        self.onArchiveAllDone = onArchiveAllDone
        self.onSetPresentationMode = onSetPresentationMode
        self.onSetNotificationsEnabled = onSetNotificationsEnabled
        self.onDispatchTask = onDispatchTask
        self.onQuit = onQuit
        self.cardHandlers = cardHandlers
    }

    private var counts: InboxTriageCounts {
        guard let snapshot = state.snapshot else { return .zero }
        return InboxTriageRules.counts(snapshot: snapshot, archivedTimestamps: state.archivedTimestamps)
    }

    private var cornerRadii: RectangleCornerRadii {
        if hasPhysicalNotch {
            return RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: isExpanded ? 20 : 16,
                bottomTrailing: isExpanded ? 20 : 16,
                topTrailing: 0
            )
        }
        let radius: CGFloat = isExpanded ? 20 : 17
        return RectangleCornerRadii(
            topLeading: radius,
            bottomLeading: radius,
            bottomTrailing: radius,
            topTrailing: radius
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            compactStrip
                .frame(height: NotchHUDMetrics.compactHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleExpand)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.10))

                InboxHubView(
                    state: state,
                    filter: $filter,
                    embeddedInNotch: true,
                    focusDispatchTrigger: focusDispatchTrigger,
                    onRefresh: onRefresh,
                    onSelectHost: onSelectHost,
                    onArchiveAllDone: onArchiveAllDone,
                    onSetPresentationMode: onSetPresentationMode,
                    onSetNotificationsEnabled: onSetNotificationsEnabled,
                    onDispatchTask: onDispatchTask,
                    onCollapse: onCollapse,
                    onQuit: onQuit,
                    cardHandlers: cardHandlers
                )
                .environment(\.colorScheme, .dark)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(
            width: isExpanded
                ? NotchHUDMetrics.expandedWidth
                : (hasPhysicalNotch ? NotchHUDMetrics.compactWidthWithNotch : NotchHUDMetrics.compactWidthFloating),
            alignment: .top
        )
        .background {
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .fill(isExpanded ? Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.95) : Color.black.opacity(0.94))
        }
        .overlay {
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isExpanded ? 0.14 : (counts.urgent > 0 ? 0.24 : 0.12)),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(isExpanded ? 0.55 : 0.35), radius: isExpanded ? 24 : 10, y: isExpanded ? 10 : 4)
        .onHover(perform: onHoverChange)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var compactStrip: some View {
        HStack(spacing: 8) {
            // Left ear: working indicator or brand status
            HStack(spacing: 6) {
                if counts.working > 0 {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.74, blue: 0.97))
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                        .opacity(pulse ? 1.0 : 0.55)
                    Text("\(counts.working) 运行中")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("Orca")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasPhysicalNotch && !isExpanded {
                // Leave room for the physical camera notch in the center.
                Spacer().frame(width: 112)
            } else {
                Spacer(minLength: 8)
            }

            // Right ear: urgent / unread / connection status badge
            rightEarStatus
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var rightEarStatus: some View {
        if state.snapshot == nil && state.problem != nil {
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 10.5))
                Text("未连接")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.orange)
        } else if state.snapshot == nil {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("同步中")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else if counts.blocked > 0 {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 10))
                Text("\(counts.urgent) 待拍板")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color(red: 0.88, green: 0.24, blue: 0.24)))
        } else if counts.waiting > 0 {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10))
                Text("\(counts.waiting) 等回复")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.42))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.orange.opacity(0.24)))
        } else if counts.unreadDone > 0 {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("\(counts.unreadDone) 新完成")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color(red: 0.43, green: 0.91, blue: 0.71))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.green.opacity(0.20)))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("顺畅")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.65))
        }
    }
}
