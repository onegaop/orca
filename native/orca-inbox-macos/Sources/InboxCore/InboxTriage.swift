import Foundation

public enum InboxFeedFilter: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case working
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: "收件箱"
        case .working: "运行中"
        case .all: "全部"
        }
    }
}

public enum InboxPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case notch
    case menubar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notch: "刘海灵动岛"
        case .menubar: "仅菜单栏"
        }
    }
}

public struct InboxTriageCounts: Equatable, Sendable {
    public let inbox: Int
    public let urgent: Int
    public let blocked: Int
    public let waiting: Int
    public let unreadDone: Int
    public let working: Int
    public let total: Int

    public init(
        inbox: Int,
        urgent: Int,
        blocked: Int,
        waiting: Int,
        unreadDone: Int,
        working: Int,
        total: Int
    ) {
        self.inbox = inbox
        self.urgent = urgent
        self.blocked = blocked
        self.waiting = waiting
        self.unreadDone = unreadDone
        self.working = working
        self.total = total
    }

    public static let zero = InboxTriageCounts(
        inbox: 0, urgent: 0, blocked: 0, waiting: 0, unreadDone: 0, working: 0, total: 0
    )
}

public enum InboxTriageRules {
    /// Only completed (`done`) rows can be archived, and a newer `updatedAt` resurfaces them automatically.
    public static func isArchived(_ row: AgentRow, archivedTimestamps: [String: Double]) -> Bool {
        guard row.stateKind == .done, let archivedAt = archivedTimestamps[row.id] else {
            return false
        }
        return archivedAt >= row.updatedAt
    }

    public static func isUnreadDone(_ row: AgentRow, archivedTimestamps: [String: Double]) -> Bool {
        row.stateKind == .done && !isArchived(row, archivedTimestamps: archivedTimestamps)
    }

    public static func isUrgent(_ row: AgentRow) -> Bool {
        row.stateKind == .blocked || row.stateKind == .waiting
    }

    public static func filteredRows(
        snapshot: Snapshot,
        filter: InboxFeedFilter,
        archivedTimestamps: [String: Double]
    ) -> [AgentRow] {
        let candidates: [AgentRow]
        switch filter {
        case .inbox:
            candidates = snapshot.agents.filter {
                isUrgent($0) || isUnreadDone($0, archivedTimestamps: archivedTimestamps)
            }
        case .working:
            candidates = snapshot.agents.filter { $0.stateKind == .working }
        case .all:
            candidates = snapshot.agents.filter { $0.bucket != nil }
        }
        return candidates.sorted { a, b in
            let rankA = sortRank(a, archivedTimestamps: archivedTimestamps)
            let rankB = sortRank(b, archivedTimestamps: archivedTimestamps)
            if rankA != rankB { return rankA < rankB }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.id < b.id
        }
    }

    public static func counts(
        snapshot: Snapshot,
        archivedTimestamps: [String: Double]
    ) -> InboxTriageCounts {
        var blocked = 0
        var waiting = 0
        var unreadDone = 0
        var working = 0
        var total = 0
        for row in snapshot.agents where row.bucket != nil {
            total += 1
            switch row.stateKind {
            case .blocked: blocked += 1
            case .waiting: waiting += 1
            case .working: working += 1
            case .done:
                if !isArchived(row, archivedTimestamps: archivedTimestamps) {
                    unreadDone += 1
                }
            case .unknown: break
            }
        }
        let urgent = blocked + waiting
        return InboxTriageCounts(
            inbox: urgent + unreadDone,
            urgent: urgent,
            blocked: blocked,
            waiting: waiting,
            unreadDone: unreadDone,
            working: working,
            total: total
        )
    }

    private static func sortRank(_ row: AgentRow, archivedTimestamps: [String: Double]) -> Int {
        switch row.stateKind {
        case .blocked: 0
        case .waiting: 1
        case .done: isArchived(row, archivedTimestamps: archivedTimestamps) ? 4 : 2
        case .working: 3
        case .unknown: 5
        }
    }
}

public struct InboxAlertEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case blocked
        case waiting
        case done
    }

    public let rowID: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let destinationURL: URL?

    public init(rowID: String, kind: Kind, title: String, body: String, destinationURL: URL?) {
        self.rowID = rowID
        self.kind = kind
        self.title = title
        self.body = body
        self.destinationURL = destinationURL
    }
}

public enum InboxTransitionDetector {
    /// Detects newly blocked, newly waiting, or newly completed agents between two snapshots of the same host.
    public static func detect(
        previous: Snapshot?,
        next: Snapshot,
        environment: String
    ) -> [InboxAlertEvent] {
        guard let previous else { return [] }
        let priorByID = Dictionary(uniqueKeysWithValues: previous.agents.map { ($0.id, $0) })
        var events: [InboxAlertEvent] = []
        for row in next.agents {
            let old = priorByID[row.id]
            let destination = SessionDestination.url(for: row, environment: environment)
            switch row.stateKind {
            case .blocked:
                if old?.stateKind != .blocked {
                    events.append(InboxAlertEvent(
                        rowID: row.id,
                        kind: .blocked,
                        title: "需要处理 · \(row.label)",
                        body: row.summaryPreview ?? "Agent 已阻塞，等待你的授权或输入。",
                        destinationURL: destination
                    ))
                }
            case .waiting:
                if old?.stateKind != .waiting && old?.stateKind != .blocked {
                    events.append(InboxAlertEvent(
                        rowID: row.id,
                        kind: .waiting,
                        title: "等待回复 · \(row.label)",
                        body: row.summaryPreview ?? "Agent 正在等你确认下一步。",
                        destinationURL: destination
                    ))
                }
            case .done:
                if old?.stateKind == .working {
                    events.append(InboxAlertEvent(
                        rowID: row.id,
                        kind: .done,
                        title: "已完成 · \(row.label)",
                        body: row.summaryPreview ?? "任务已完成，点击查看结果。",
                        destinationURL: destination
                    ))
                }
            case .working, .unknown:
                break
            }
        }
        return events
    }
}
