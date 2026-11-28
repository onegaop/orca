import Foundation

public enum Bucket: String, CaseIterable, Identifiable, Sendable {
    case attention, working, done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .attention: "待处理"
        case .working: "进行中"
        case .done: "已完成"
        }
    }

    public var icon: String {
        switch self {
        case .attention: "bell.badge"
        case .working: "waveform"
        case .done: "checkmark.circle"
        }
    }
}

public enum AgentStateKind: String, Sendable, Equatable {
    case blocked
    case waiting
    case working
    case done
    case unknown

    public init(rawState: String) {
        switch rawState {
        case "blocked": self = .blocked
        case "waiting": self = .waiting
        case "working": self = .working
        case "done": self = .done
        default: self = .unknown
        }
    }

    public var label: String {
        switch self {
        case .blocked: "阻塞"
        case .waiting: "等你"
        case .working: "进行中"
        case .done: "已完成"
        case .unknown: "未知"
        }
    }

    public var symbolName: String {
        switch self {
        case .blocked: "exclamationmark.octagon.fill"
        case .waiting: "clock.badge.exclamationmark"
        case .working: "waveform"
        case .done: "checkmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

public struct AgentRow: Decodable, Identifiable, Sendable {
    public let orcaSessionId: String?
    public let kind: String?
    public let agent: String?
    public let state: String
    public let worktreeId: String
    public let workspace: String
    public let repo: String?
    public let hostId: String?
    public let paneKey: String
    public let title: String?
    public let lastAssistantMessage: String?
    public let updatedAt: Double

    public init(
        orcaSessionId: String? = nil,
        kind: String? = nil,
        agent: String? = nil,
        state: String,
        worktreeId: String,
        workspace: String,
        repo: String? = nil,
        hostId: String? = nil,
        paneKey: String,
        title: String? = nil,
        lastAssistantMessage: String? = nil,
        updatedAt: Double
    ) {
        self.orcaSessionId = orcaSessionId
        self.kind = kind
        self.agent = agent
        self.state = state
        self.worktreeId = worktreeId
        self.workspace = workspace
        self.repo = repo
        self.hostId = hostId
        self.paneKey = paneKey
        self.title = title
        self.lastAssistantMessage = lastAssistantMessage
        self.updatedAt = updatedAt
    }

    public var id: String { [hostId ?? "local", worktreeId, paneKey].joined(separator: "\u{001F}") }

    public var isChat: Bool { kind == "chat" }

    public var stateKind: AgentStateKind { AgentStateKind(rawState: state) }

    public var bucket: Bucket? {
        switch state {
        case "blocked", "waiting": .attention
        case "working": .working
        case "done": .done
        default: nil
        }
    }

    public var stateLabel: String { stateKind.label }

    public var project: String { repo.flatMap { $0.isEmpty ? nil : $0 } ?? "未标记项目" }

    public var label: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? agent ?? "Agent 会话" }

    /// Subtitle for the row, omitting the agent name when it is already used as the primary title.
    public var subtitleAgent: String? {
        guard let agent, !agent.isEmpty else { return nil }
        return agent == label ? nil : agent
    }

    /// Compact project/workspace/agent context tag for flat triage cards.
    public var contextTag: String {
        var parts: [String] = []
        if let repo, !repo.isEmpty {
            parts.append(repo)
        } else if !workspace.isEmpty && workspace != label {
            parts.append(workspace)
        }
        if let agent, !agent.isEmpty {
            parts.append(agent)
        }
        return parts.joined(separator: " · ")
    }

    /// Plain-text preview of the agent's latest reply with lightweight Markdown cleanup.
    public var summaryPreview: String? {
        guard let raw = lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        var text = raw
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > 220 ? String(text.prefix(219)) + "…" : text
    }

    public var date: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
}

public struct Project: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let host: String?
    public let workspaces: [Workspace]

    public init(id: String, title: String, host: String?, workspaces: [Workspace]) {
        self.id = id
        self.title = title
        self.host = host
        self.workspaces = workspaces
    }

    public var allRows: [AgentRow] { workspaces.flatMap(\.rows) }
    public var totalCount: Int { allRows.count }
    public var blockedCount: Int { allRows.filter { $0.stateKind == .blocked }.count }
    public var waitingCount: Int { allRows.filter { $0.stateKind == .waiting }.count }
    public var hasBlocked: Bool { blockedCount > 0 }
}

public struct Workspace: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let rows: [AgentRow]

    public init(id: String, title: String, rows: [AgentRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }

    public var blockedCount: Int { rows.filter { $0.stateKind == .blocked }.count }
}

public struct Snapshot: Decodable, Sendable {
    public let agents: [AgentRow]
    public let truncated: Bool

    public init(agents: [AgentRow], truncated: Bool = false) {
        self.agents = agents
        self.truncated = truncated
    }

    public func rows(in bucket: Bucket) -> [AgentRow] {
        agents.filter { $0.bucket == bucket }.sorted { a, b in
            if bucket == .attention, a.state != b.state { return a.state == "blocked" }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.id < b.id
        }
    }

    public func count(in bucket: Bucket) -> Int {
        rows(in: bucket).count
    }

    public var blockedCount: Int {
        agents.filter { $0.stateKind == .blocked }.count
    }

    public func projects(in bucket: Bucket) -> [Project] {
        typealias Key = String
        let rows = rows(in: bucket)
        func key(_ row: AgentRow) -> Key {
            // Git worktrees carry repo id before "::". Fall back to display name on older/folder rows.
            let parts = row.worktreeId.components(separatedBy: "::")
            return [row.hostId ?? "local", parts.count > 1 ? parts[0] : row.project].joined(separator: "\u{001F}")
        }
        let grouped = Dictionary(grouping: rows, by: key)
        var seen = Set<Key>()
        return rows.compactMap { first in
            let id = key(first)
            guard seen.insert(id).inserted, let projectRows = grouped[id] else { return nil }
            let byWorkspace = Dictionary(grouping: projectRows, by: \.worktreeId)
            var workspaceIDs = Set<String>()
            let workspaces = projectRows.compactMap { row -> Workspace? in
                guard workspaceIDs.insert(row.worktreeId).inserted else { return nil }
                return Workspace(id: row.worktreeId, title: row.workspace, rows: byWorkspace[row.worktreeId] ?? [])
            }
            return Project(id: id, title: first.project, host: first.hostId, workspaces: workspaces)
        }
    }
}

public struct HostTarget: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isLocal: Bool

    public init(id: String, name: String, isLocal: Bool) {
        self.id = id
        self.name = name
        self.isLocal = isLocal
    }

    public static let local = HostTarget(id: "local", name: "本机", isLocal: true)

    public var displayName: String {
        if isLocal {
            return name == "本机" || name.isEmpty ? "本机" : "本机（\(name)）"
        }
        return name
    }

    public var symbolName: String {
        if isLocal { return "laptopcomputer" }
        let lower = name.lowercased()
        if lower.contains("mini") { return "macmini" }
        return "desktopcomputer"
    }
}

public func decodeHosts(_ data: Data) -> [HostTarget] {
    struct RawHost: Decodable {
        let kind: String
        let name: String
        let id: String
        let machineName: String?
    }
    struct ResultPayload: Decodable { let hosts: [RawHost] }
    struct Envelope: Decodable {
        let ok: Bool
        let result: ResultPayload?
    }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
          envelope.ok,
          let rawHosts = envelope.result?.hosts else {
        return [.local]
    }
    var seen = Set<String>()
    let parsed = rawHosts.compactMap { raw -> HostTarget? in
        guard raw.kind == "local" || raw.kind == "environment" else { return nil }
        let id = raw.kind == "local" ? "local" : raw.id
        guard !id.isEmpty, seen.insert(id).inserted else { return nil }
        if raw.kind == "local" {
            let label = raw.machineName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return HostTarget(id: "local", name: (label?.isEmpty == false ? label! : "本机"), isLocal: true)
        }
        let name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return HostTarget(id: id, name: name.isEmpty ? id : name, isLocal: false)
    }
    return parsed.isEmpty ? [.local] : parsed
}

public enum InboxFailure: LocalizedError {
    case missingCLI, timeout, unreadable, rejected(String)

    public var errorDescription: String? {
        switch self {
        case .missingCLI: "找不到 Orca CLI。请先确认本机已安装 Orca。"
        case .timeout: "Orca 暂未响应。"
        case .unreadable: "这版 Orca 返回了收件箱暂不认识的数据。"
        case .rejected(let code):
            code == "runtime_access_denied"
                ? "收件箱没有权限连接 Orca。"
                : "连不上当前 Orca 环境。请确认本机或远程 Orca 正在运行。"
        }
    }
}

public func decodeSnapshot(_ data: Data) throws -> Snapshot {
    struct Envelope: Decodable {
        struct Problem: Decodable { let code: String }
        let ok: Bool
        let result: Snapshot?
        let error: Problem?
    }
    let envelope: Envelope
    do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
    catch { throw InboxFailure.unreadable }
    guard envelope.ok else { throw InboxFailure.rejected(envelope.error?.code ?? "") }
    guard let result = envelope.result else { throw InboxFailure.unreadable }
    return result
}

public enum CompactRelativeTime {
    public static func string(updatedAtMs: Double, relativeTo now: Date) -> String {
        guard updatedAtMs > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: updatedAtMs / 1000)
        return string(from: date, relativeTo: now)
    }

    public static func string(from date: Date, relativeTo now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "刚刚" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)分前" }
        let hours = Int(elapsed / 3600)
        if hours < 24 { return "\(hours)小时前" }
        let days = Int(elapsed / 86_400)
        if days < 30 { return "\(days)天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

/// Pure view-layer state for the inbox popover & Notch HUD, independent of live CLI fetching.
public struct InboxPanelState: Sendable {
    public var snapshot: Snapshot?
    public var updated: Date?
    public var problem: String?
    public var refreshing: Bool
    public var referenceDate: Date?
    public var hosts: [HostTarget]
    public var selectedHost: HostTarget
    public var stale: Bool
    public var actionProblem: String?
    public var archivedTimestamps: [String: Double]
    public var presentationMode: InboxPresentationMode
    public var notificationsEnabled: Bool
    public var dispatchWorkspaces: [DispatchWorkspaceOption]
    public var installedAgents: [InstalledAgentOption]
    public var defaultDispatchWorktreeId: String?
    public var defaultDispatchAgent: String
    public var toastMessage: String?

    public init(
        snapshot: Snapshot? = nil,
        updated: Date? = nil,
        problem: String? = nil,
        refreshing: Bool = false,
        referenceDate: Date? = nil,
        hosts: [HostTarget] = [.local],
        selectedHost: HostTarget = .local,
        stale: Bool = false,
        actionProblem: String? = nil,
        archivedTimestamps: [String: Double] = [:],
        presentationMode: InboxPresentationMode = .notch,
        notificationsEnabled: Bool = true,
        dispatchWorkspaces: [DispatchWorkspaceOption] = [],
        installedAgents: [InstalledAgentOption] = [],
        defaultDispatchWorktreeId: String? = nil,
        defaultDispatchAgent: String = "codex",
        toastMessage: String? = nil
    ) {
        self.snapshot = snapshot
        self.updated = updated
        self.problem = problem
        self.refreshing = refreshing
        self.referenceDate = referenceDate
        self.hosts = hosts.isEmpty ? [.local] : hosts
        self.selectedHost = selectedHost
        self.stale = stale
        self.actionProblem = actionProblem
        self.archivedTimestamps = archivedTimestamps
        self.presentationMode = presentationMode
        self.notificationsEnabled = notificationsEnabled
        self.dispatchWorkspaces = dispatchWorkspaces
        self.installedAgents = installedAgents
        self.defaultDispatchWorktreeId = defaultDispatchWorktreeId
        self.defaultDispatchAgent = defaultDispatchAgent
        self.toastMessage = toastMessage
    }

    public var isDisconnectedWithStaleData: Bool {
        problem != nil && snapshot != nil
    }

    public var isDisconnectedWithoutData: Bool {
        problem != nil && snapshot == nil
    }

    public var isInitialLoading: Bool {
        snapshot == nil && problem == nil
    }

    public var effectiveNow: Date {
        referenceDate ?? updated ?? .now
    }
}
