import Foundation

public enum SessionDestination {
    public static func url(for row: AgentRow, environment: String) -> URL? {
        guard let sessionID = row.orcaSessionId,
              valid(environment, limit: 256), valid(row.worktreeId, limit: 4096),
              valid(row.paneKey, limit: 512), valid(sessionID, limit: 128),
              row.paneKey.range(of: #"^[^:]+:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression) != nil,
              sessionID.range(of: #"^[A-Za-z0-9_-]{8,128}$"#, options: .regularExpression) != nil,
              !sessionID.hasPrefix("term_"), !sessionID.hasPrefix("structworker_"),
              row.hostId.map(validHost) != false else { return nil }
        var components = URLComponents()
        components.scheme = "orca"
        components.host = "inbox"
        components.path = "/session"
        components.queryItems = [
            URLQueryItem(name: "environment", value: environment),
            URLQueryItem(name: "workspace", value: row.worktreeId),
            URLQueryItem(name: "pane", value: row.paneKey),
            URLQueryItem(name: "id", value: sessionID)
        ]
        if let hostID = row.hostId {
            components.queryItems?.append(URLQueryItem(name: "host", value: hostID))
        }
        // URLSearchParams interprets literal plus as space, unlike URLComponents.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url, url.absoluteString.utf8.count <= 8192 else { return nil }
        return url
    }

    private static func valid(_ value: String, limit: Int) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf16.count <= limit
            && value.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control }
    }

    private static func validHost(_ value: String) -> Bool {
        guard valid(value, limit: 512) else { return false }
        if value == "local" { return true }
        guard value.hasPrefix("ssh:") || value.hasPrefix("runtime:"),
              let separator = value.firstIndex(of: ":") else { return false }
        let tail = String(value[value.index(after: separator)...])
        guard !tail.isEmpty, !tail.contains("|"), let decoded = tail.removingPercentEncoding else { return false }
        return !decoded.isEmpty && !(value.hasPrefix("runtime:") && decoded == "unresolved-owner")
    }
}

public struct InboxMenuStatus: Sendable {
    public let text: String
    public let symbolName: String
    public let description: String

    public init(state: InboxPanelState) {
        let host = state.selectedHost.displayName
        if let snapshot = state.snapshot {
            let count = snapshot.count(in: .attention)
            let partial = snapshot.truncated ? "+" : ""
            let stale = state.stale || state.problem != nil
            text = "\(count)\(partial)\(stale ? "~" : "")"
            symbolName = stale ? "clock.arrow.circlepath" : "tray"
            description = "\(host) · \(snapshot.truncated ? "至少 " : "")\(count) 项待处理\(stale ? " · 旧数据" : "")\(state.refreshing ? " · 正在刷新" : "")"
        } else if state.problem != nil {
            text = "!"
            symbolName = "bolt.horizontal.circle"
            description = "\(host) · 未连接 · 待处理数量未知"
        } else {
            text = "…"
            symbolName = "tray"
            description = "\(host) · 正在读取待处理数量"
        }
    }
}
