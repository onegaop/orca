import Foundation

public struct AgentTranscriptTool: Decodable, Equatable, Sendable {
    public let name: String
    public let state: String?

    public init(name: String, state: String? = nil) {
        self.name = name
        self.state = state
    }
}

public struct AgentTranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: String
    public let role: String?
    public let text: String
    public let pending: Bool
    public let tools: [AgentTranscriptTool]

    public init(
        id: Int,
        kind: String,
        role: String? = nil,
        text: String,
        pending: Bool = false,
        tools: [AgentTranscriptTool] = []
    ) {
        self.id = id
        self.kind = kind
        self.role = role
        self.text = text
        self.pending = pending
        self.tools = tools
    }
}

public struct AgentTranscriptPage: Equatable, Sendable {
    public let state: String?
    public let entries: [AgentTranscriptEntry]
    public let limited: Bool

    public init(state: String? = nil, entries: [AgentTranscriptEntry], limited: Bool = false) {
        self.state = state
        self.entries = entries
        self.limited = limited
    }
}

public func decodeTranscriptPage(_ data: Data) throws -> AgentTranscriptPage {
    struct RawEntry: Decodable {
        let kind: String
        let role: String?
        let text: String?
        let name: String?
        let state: String?
        let pending: Bool?
        let tools: [AgentTranscriptTool]?
    }
    struct ResultPayload: Decodable {
        let state: String?
        let entries: [RawEntry]
        let limited: Bool?
    }
    struct Envelope: Decodable {
        struct Problem: Decodable { let code: String; let message: String? }
        let ok: Bool
        let result: ResultPayload?
        let error: Problem?
    }
    let envelope: Envelope
    do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
    catch { throw InboxFailure.unreadable }
    guard envelope.ok else { throw InboxFailure.rejected(envelope.error?.code ?? "") }
    guard let payload = envelope.result else { throw InboxFailure.unreadable }
    let entries = payload.entries.enumerated().map { index, raw in
        let body = raw.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? raw.name.map { "工具：\($0)" }
            ?? ""
        return AgentTranscriptEntry(
            id: index,
            kind: raw.kind,
            role: raw.role,
            text: body,
            pending: raw.pending ?? false,
            tools: raw.tools ?? []
        )
    }
    return AgentTranscriptPage(state: payload.state, entries: entries, limited: payload.limited ?? false)
}

public struct AgentPromptOption: Identifiable, Equatable, Sendable, Decodable {
    public let id: String
    public let label: String
    public let kind: String?

    public init(id: String, label: String, kind: String? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

public struct AgentPendingPrompt: Identifiable, Equatable, Sendable, Decodable {
    public let itemId: String
    public let revision: Int
    public let kind: String
    public let title: String
    public let detail: String?
    public let questionId: String?
    public let options: [AgentPromptOption]

    public var id: String { "\(itemId):\(revision)" }

    public init(
        itemId: String,
        revision: Int,
        kind: String,
        title: String,
        detail: String? = nil,
        questionId: String? = nil,
        options: [AgentPromptOption] = []
    ) {
        self.itemId = itemId
        self.revision = revision
        self.kind = kind
        self.title = title
        self.detail = detail
        self.questionId = questionId
        self.options = options
    }
}

public func decodePendingPrompts(_ data: Data) -> [AgentPendingPrompt] {
    struct ResultPayload: Decodable { let prompts: [AgentPendingPrompt] }
    struct Envelope: Decodable {
        let ok: Bool
        let result: ResultPayload?
    }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
          envelope.ok,
          let prompts = envelope.result?.prompts else {
        return []
    }
    return prompts
}

public struct InstalledAgentOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    public static let defaults: [InstalledAgentOption] = [
        InstalledAgentOption(id: "codex", label: "Codex"),
        InstalledAgentOption(id: "claude", label: "Claude"),
        InstalledAgentOption(id: "antigravity", label: "Antigravity")
    ]
}

public func decodeInstalledAgents(_ data: Data) -> [InstalledAgentOption] {
    struct RawAgent: Decodable {
        let id: String
        let name: String?
        let label: String?
        let installed: Bool?
    }
    struct ResultPayload: Decodable { let agents: [RawAgent] }
    struct Envelope: Decodable {
        let ok: Bool
        let result: ResultPayload?
    }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
          envelope.ok,
          let rawAgents = envelope.result?.agents else {
        return InstalledAgentOption.defaults
    }
    let parsed = rawAgents.compactMap { raw -> InstalledAgentOption? in
        guard raw.installed != false, !raw.id.isEmpty else { return nil }
        let title = raw.label ?? raw.name ?? raw.id.capitalized
        return InstalledAgentOption(id: raw.id, label: title)
    }
    return parsed.isEmpty ? InstalledAgentOption.defaults : parsed
}

public struct DispatchWorkspaceOption: Identifiable, Hashable, Sendable {
    public let worktreeId: String
    public let project: String
    public let workspace: String

    public var id: String { worktreeId }

    public var displayLabel: String {
        if project.isEmpty || project == "未标记项目" || project == workspace {
            return workspace
        }
        return "\(project) · \(workspace)"
    }

    public init(worktreeId: String, project: String, workspace: String) {
        self.worktreeId = worktreeId
        self.project = project
        self.workspace = workspace
    }

    /// Derives unique dispatchable workspaces from the current snapshot, preserving most-recent ordering.
    public static func fromSnapshot(_ snapshot: Snapshot) -> [DispatchWorkspaceOption] {
        var seen = Set<String>()
        let sorted = snapshot.agents.sorted { $0.updatedAt > $1.updatedAt }
        return sorted.compactMap { row in
            guard !row.worktreeId.isEmpty, seen.insert(row.worktreeId).inserted else { return nil }
            return DispatchWorkspaceOption(
                worktreeId: row.worktreeId,
                project: row.project,
                workspace: row.workspace
            )
        }
    }
}
