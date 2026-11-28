import SwiftUI
import InboxCore

public struct InboxCardHandlers {
    public let onOpenSession: (AgentRow) -> Void
    public let onCopySessionID: (String) -> Void
    public let onOpenOrca: () -> Void
    public let onArchive: (AgentRow) -> Void
    public let onUnarchive: (AgentRow) -> Void
    public let onLoadTranscript: (AgentRow) async throws -> AgentTranscriptPage
    public let onLoadPendingPrompts: (AgentRow) async -> [AgentPendingPrompt]
    public let onReply: (AgentRow, String) async throws -> Void
    public let onRespondPrompt: (AgentRow, AgentPendingPrompt, AgentPromptOption) async throws -> Void

    public init(
        onOpenSession: @escaping (AgentRow) -> Void = { _ in },
        onCopySessionID: @escaping (String) -> Void = { _ in },
        onOpenOrca: @escaping () -> Void = {},
        onArchive: @escaping (AgentRow) -> Void = { _ in },
        onUnarchive: @escaping (AgentRow) -> Void = { _ in },
        onLoadTranscript: @escaping (AgentRow) async throws -> AgentTranscriptPage = { _ in
            AgentTranscriptPage(entries: [])
        },
        onLoadPendingPrompts: @escaping (AgentRow) async -> [AgentPendingPrompt] = { _ in [] },
        onReply: @escaping (AgentRow, String) async throws -> Void = { _, _ in },
        onRespondPrompt: @escaping (AgentRow, AgentPendingPrompt, AgentPromptOption) async throws -> Void = { _, _, _ in }
    ) {
        self.onOpenSession = onOpenSession
        self.onCopySessionID = onCopySessionID
        self.onOpenOrca = onOpenOrca
        self.onArchive = onArchive
        self.onUnarchive = onUnarchive
        self.onLoadTranscript = onLoadTranscript
        self.onLoadPendingPrompts = onLoadPendingPrompts
        self.onReply = onReply
        self.onRespondPrompt = onRespondPrompt
    }
}

struct InboxTaskCardView: View {
    let row: AgentRow
    let environment: String
    let referenceNow: Date
    let isArchived: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let isReplying: Bool
    let handlers: InboxCardHandlers
    let onToggleExpand: () -> Void
    let onToggleReply: () -> Void

    @State private var transcript: AgentTranscriptPage?
    @State private var loadingTranscript = false
    @State private var transcriptError: String?
    @State private var pendingPrompts: [AgentPendingPrompt] = []
    @State private var loadingPrompts = false
    @State private var replyText = ""
    @State private var sendingAction = false
    @State private var inlineError: String?
    @FocusState private var replyFocused: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    private var canOpenSession: Bool {
        SessionDestination.url(for: row, environment: environment) != nil
    }

    private var canInteractBySessionID: Bool {
        guard let id = row.orcaSessionId, !id.isEmpty else { return false }
        return !id.hasPrefix("term_") && !id.hasPrefix("structworker_")
    }

    private var accentColor: Color {
        switch row.stateKind {
        case .blocked: InboxPalette.blockedFill(colorScheme: colorScheme)
        case .waiting: InboxPalette.waitingInk(colorScheme: colorScheme)
        case .working: InboxPalette.workingInk(colorScheme: colorScheme)
        case .done: isArchived ? .secondary.opacity(0.4) : InboxPalette.doneInk(colorScheme: colorScheme)
        case .unknown: .secondary.opacity(0.4)
        }
    }

    private var cardBackground: Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        if row.stateKind == .blocked {
            return InboxPalette.blockedFill(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.08)
        }
        if row.stateKind == .waiting {
            return InboxPalette.waitingInk(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.07)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.035)
    }

    private var cardBorder: Color {
        if isSelected {
            return Color.accentColor.opacity(0.65)
        }
        if row.stateKind == .blocked {
            return InboxPalette.blockedInk(colorScheme: colorScheme).opacity(0.35)
        }
        if row.stateKind == .waiting {
            return InboxPalette.waitingInk(colorScheme: colorScheme).opacity(0.30)
        }
        return Color(nsColor: .separatorColor).opacity(reduceTransparency ? 0.85 : 0.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            headerRow
            summaryBody
            if !pendingPrompts.isEmpty {
                pendingPromptsSection
            }
            if isExpanded {
                expandedTranscriptSection
            }
            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 11))
                    .foregroundStyle(InboxPalette.blockedInk(colorScheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionRow
            if isReplying {
                replyComposer
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 11)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: isSelected ? 1.3 : 0.8)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 9)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .contextMenu {
            if canOpenSession {
                Button("在 Orca 中打开此会话") { handlers.onOpenSession(row) }
            }
            if row.stateKind == .done {
                if isArchived {
                    Button("移回收件箱（标记未读）") { handlers.onUnarchive(row) }
                } else {
                    Button("已读归档") { handlers.onArchive(row) }
                }
            }
            if let id = row.orcaSessionId {
                Button("复制 Orca 会话 ID") { handlers.onCopySessionID(id) }
            }
            Divider()
            Button("打开 Orca 主窗口") { handlers.onOpenOrca() }
        }
        .task(id: "\(row.id):\(row.state):\(row.updatedAt)") {
            guard canInteractBySessionID && row.isChat && (row.stateKind == .blocked || row.stateKind == .waiting) else {
                pendingPrompts = []
                return
            }
            loadingPrompts = true
            let loaded = await handlers.onLoadPendingPrompts(row)
            if !Task.isCancelled {
                pendingPrompts = loaded
                loadingPrompts = false
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                loadTranscriptIfNeeded()
            }
        }
        .onChange(of: isReplying) { _, replying in
            if replying {
                replyFocused = true
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: row.stateKind.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InboxPalette.iconColor(for: row.stateKind, colorScheme: colorScheme))
                .accessibilityHidden(true)

            Text(row.label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if !row.contextTag.isEmpty {
                Text(row.contextTag)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055))
                    }
            }

            Spacer(minLength: 6)

            StatusBadgeView(kind: row.stateKind)
                .fixedSize()

            Text(CompactRelativeTime.string(updatedAtMs: row.updatedAt, relativeTo: referenceNow))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var summaryBody: some View {
        if let summary = row.summaryPreview {
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(isExpanded ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if row.stateKind == .working {
            Text("Agent 正在后台执行任务…")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        } else if row.stateKind == .blocked || row.stateKind == .waiting {
            Text(loadingPrompts ? "正在读取待确认内容…" : "等待你确认下一步，点击展开查看或直接回复。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private var pendingPromptsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pendingPrompts) { prompt in
                VStack(alignment: .leading, spacing: 5) {
                    Text(prompt.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = prompt.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                            }
                    }

                    if !prompt.options.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(prompt.options.prefix(3)) { option in
                                let isDeny = option.kind == "reject" || option.id.lowercased().contains("reject") || option.id.lowercased().contains("deny")
                                Button {
                                    submitPromptOption(prompt: prompt, option: option)
                                } label: {
                                    Text(option.label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isDeny ? .red : .green)
                                .controlSize(.mini)
                                .disabled(sendingAction)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                }
            }
        }
    }

    private var expandedTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().opacity(0.6)
            if loadingTranscript {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在拉取最近对话…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let transcriptError {
                Text(transcriptError)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let entries = transcript?.entries, !entries.isEmpty {
                ForEach(entries.suffix(4)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(entryBadgeLabel(entry))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(entryBadgeColor(entry))
                            if entry.pending {
                                Text("等待确认")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(InboxPalette.waitingInk(colorScheme: colorScheme))
                            }
                        }
                        if !entry.text.isEmpty {
                            Text(entry.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.primary.opacity(0.86))
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        if !entry.tools.isEmpty {
                            Text(entry.tools.map { "⚙ \($0.name)" }.joined(separator: "  "))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("暂无更多对话记录。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if canInteractBySessionID {
                Button(action: onToggleReply) {
                    Label(
                        row.stateKind == .working ? "插队一句" : "快速回复",
                        systemImage: isReplying ? "chevron.up" : "bubble.left"
                    )
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(sendingAction)

                Button(action: onToggleExpand) {
                    Label(
                        isExpanded ? "收起对话" : "看对话",
                        systemImage: isExpanded ? "text.alignleft" : "doc.plaintext"
                    )
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if row.stateKind == .done {
                if isArchived {
                    Button {
                        handlers.onUnarchive(row)
                    } label: {
                        Label("标为未读", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Button {
                        handlers.onArchive(row)
                    } label: {
                        Label("已读归档", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            Spacer(minLength: 4)

            if canOpenSession {
                Button {
                    handlers.onOpenSession(row)
                } label: {
                    Label("进 Orca", systemImage: "arrow.up.forward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("在 Orca 中精准打开此会话")
            }
        }
    }

    private var replyComposer: some View {
        HStack(spacing: 6) {
            TextField(
                "直接回复 \(row.agent ?? "Agent")（回车发送）…",
                text: $replyText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($replyFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 0.8)
            }
            .disabled(sendingAction)
            .onSubmit(submitReply)

            Button(action: submitReply) {
                if sendingAction {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("发送")
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(sendingAction || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 2)
    }

    private func loadTranscriptIfNeeded() {
        guard canInteractBySessionID, !loadingTranscript else { return }
        loadingTranscript = true
        transcriptError = nil
        Task {
            do {
                let page = try await handlers.onLoadTranscript(row)
                await MainActor.run {
                    transcript = page
                    loadingTranscript = false
                }
            } catch {
                await MainActor.run {
                    transcriptError = error.localizedDescription
                    loadingTranscript = false
                }
            }
        }
    }

    private func submitReply() {
        let message = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sendingAction else { return }
        sendingAction = true
        inlineError = nil
        Task {
            do {
                try await handlers.onReply(row, message)
                await MainActor.run {
                    replyText = ""
                    sendingAction = false
                    onToggleReply()
                }
            } catch {
                await MainActor.run {
                    inlineError = error.localizedDescription
                    sendingAction = false
                }
            }
        }
    }

    private func submitPromptOption(prompt: AgentPendingPrompt, option: AgentPromptOption) {
        guard !sendingAction else { return }
        sendingAction = true
        inlineError = nil
        Task {
            do {
                try await handlers.onRespondPrompt(row, prompt, option)
                await MainActor.run {
                    pendingPrompts.removeAll { $0.itemId == prompt.itemId }
                    sendingAction = false
                }
            } catch {
                await MainActor.run {
                    inlineError = error.localizedDescription
                    sendingAction = false
                }
            }
        }
    }

    private func entryBadgeLabel(_ entry: AgentTranscriptEntry) -> String {
        switch entry.kind {
        case "approval": "权限审批"
        case "question": "等待提问"
        case "error": "错误"
        case "tool": "工具"
        default:
            entry.role == "user" ? "你" : (row.agent ?? "Agent")
        }
    }

    private func entryBadgeColor(_ entry: AgentTranscriptEntry) -> Color {
        switch entry.kind {
        case "approval", "error": InboxPalette.blockedInk(colorScheme: colorScheme)
        case "question": InboxPalette.waitingInk(colorScheme: colorScheme)
        default: entry.role == "user" ? .accentColor : .secondary
        }
    }
}
