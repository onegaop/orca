import Foundation
import Testing
@testable import InboxCore

private let pane = "tab-a:12345678-1234-4234-9234-123456789abc"

private func destinationRow(sessionID: String? = "session_123", workspace: String = "repo::/项目/a+b & c#d?x=1", host: String? = "ssh:mini%2B1") -> AgentRow {
    AgentRow(orcaSessionId: sessionID, state: "waiting", worktreeId: workspace, workspace: "main", hostId: host, paneKey: pane, updatedAt: 0)
}

@Test func sessionDestinationPreservesIdentityAcrossQueryEncoding() throws {
    let url = try #require(SessionDestination.url(for: destinationRow(), environment: "env+mini"))
    #expect(!url.absoluteString.contains("+"))
    #expect(!url.absoluteString.contains("#"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
    #expect(components.scheme == "orca")
    #expect(components.host == "inbox")
    #expect(components.path == "/session")
    #expect(values["environment"] == "env+mini")
    #expect(values["workspace"] == "repo::/项目/a+b & c#d?x=1")
    #expect(values["pane"] == pane)
    #expect(values["id"] == "session_123")
    #expect(values["host"] == "ssh:mini%2B1")
}

@Test func sessionDestinationRequiresStableIdentityAndValidHost() {
    for id in [nil, "", "short", " term_1234", "term_12345678", "structworker_123456", "session\n1234"] {
        #expect(SessionDestination.url(for: destinationRow(sessionID: id), environment: "local") == nil)
    }
    for host in ["", "mini", "ssh:", "ssh:a|b", "ssh:%ZZ", "runtime:unresolved-owner", "runtime:%75nresolved-owner"] {
        #expect(SessionDestination.url(for: destinationRow(host: host), environment: "local") == nil)
    }
    #expect(SessionDestination.url(for: destinationRow(host: nil), environment: "local") != nil)
    #expect(SessionDestination.url(for: destinationRow(workspace: " r::w"), environment: "local") == nil)
    #expect(SessionDestination.url(for: destinationRow(), environment: "local\n") == nil)
    let legacyPane = AgentRow(orcaSessionId: "session_123", state: "waiting", worktreeId: "r::w", workspace: "main", paneKey: "tab:1", updatedAt: 0)
    #expect(SessionDestination.url(for: legacyPane, environment: "local") == nil)
}
