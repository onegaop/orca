import Foundation
import AppKit
import SwiftUI
import Testing
@testable import InboxCore
@testable import InboxUI

private func sample() throws -> Snapshot {
    let rows: [[String: Any]] = [
        ["hostId": "mini", "worktreeId": "repo-1::path-a", "paneKey": "a", "repo": "H5", "workspace": "main", "state": "waiting", "updatedAt": 3000],
        ["hostId": "mini", "worktreeId": "repo-1::path-b", "paneKey": "b", "repo": "H5", "workspace": "dev", "state": "blocked", "updatedAt": 1000],
        ["hostId": "mini", "worktreeId": "repo-1::path-b", "paneKey": "c", "repo": "H5", "workspace": "dev", "state": "working", "updatedAt": 4000],
        ["hostId": "mini", "worktreeId": "repo-2::path-c", "paneKey": "d", "repo": "H5", "workspace": "dev", "state": "waiting", "updatedAt": 2000],
        ["hostId": "other", "worktreeId": "repo-1::path-a", "paneKey": "a", "repo": "H5", "workspace": "main", "state": "waiting", "updatedAt": 1500],
        ["worktreeId": "folder:x", "paneKey": "e", "workspace": "Docs", "state": "done", "updatedAt": 5000],
        ["worktreeId": "folder:y", "paneKey": "f", "workspace": "Other", "state": "future", "updatedAt": 6000]
    ]
    let json = try JSONSerialization.data(withJSONObject: ["ok": true, "result": ["agents": rows, "truncated": true]])
    return try decodeSnapshot(json)
}

@Test func prioritiesAndCounts() throws {
    let data = try sample()
    #expect(data.rows(in: .attention).map(\.state) == ["blocked", "waiting", "waiting", "waiting"])
    #expect(data.rows(in: .working).count == 1)
    #expect(data.rows(in: .done).count == 1)
    #expect(data.blockedCount == 1)
    #expect(data.truncated)
}

@Test func groupsDoNotMergeByDisplayNameOrAcrossHosts() throws {
    let groups = try sample().projects(in: .attention)
    #expect(groups.count == 3)
    #expect(groups[0].workspaces.map(\.title) == ["dev", "main"])
    #expect(groups[0].blockedCount == 1)
    #expect(groups[0].waitingCount == 1)
    #expect(groups[0].totalCount == 2)
    #expect(Set(groups.flatMap(\.workspaces).flatMap(\.rows).map(\.id)).count == 4)
}

@Test func failureIsNotAnEmptyInbox() {
    #expect(throws: InboxFailure.self) {
        try decodeSnapshot(Data(#"{"ok":false,"error":{"code":"runtime_access_denied"}}"#.utf8))
    }
    #expect(throws: InboxFailure.self) {
        try decodeSnapshot(Data(#"{"ok":true,"result":{}}"#.utf8))
    }
}

@Test func compactRelativeTimeIsStableAndConcise() {
    let now = Date(timeIntervalSince1970: 1_795_788_000)
    #expect(CompactRelativeTime.string(updatedAtMs: 0, relativeTo: now) == "—")
    #expect(CompactRelativeTime.string(from: now.addingTimeInterval(-20), relativeTo: now) == "刚刚")
    #expect(CompactRelativeTime.string(from: now.addingTimeInterval(-180), relativeTo: now) == "3分前")
    #expect(CompactRelativeTime.string(from: now.addingTimeInterval(-7_200), relativeTo: now) == "2小时前")
    #expect(CompactRelativeTime.string(from: now.addingTimeInterval(-172_800), relativeTo: now) == "2天前")
    #expect(CompactRelativeTime.string(from: now.addingTimeInterval(-3_000_000), relativeTo: now).contains("/"))
}

@Test func subtitleAgentAvoidsDuplicatingFallbackTitle() {
    let withTitle = AgentRow(
        agent: "Claude",
        state: "blocked",
        worktreeId: "r::w",
        workspace: "main",
        paneKey: "p1",
        title: "修复接口超时",
        updatedAt: 1000
    )
    #expect(withTitle.label == "修复接口超时")
    #expect(withTitle.subtitleAgent == "Claude")

    let withoutTitle = AgentRow(
        agent: "Claude",
        state: "waiting",
        worktreeId: "r::w",
        workspace: "main",
        paneKey: "p2",
        title: nil,
        updatedAt: 1000
    )
    #expect(withoutTitle.label == "Claude")
    #expect(withoutTitle.subtitleAgent == nil)
}

@Test func fixtureStatesCoverAllFourScenarios() {
    // 1. Has tasks (blocked first, long project name preserved)
    let hasTasks = InboxFixtures.hasTasksState
    #expect(hasTasks.snapshot != nil)
    #expect(hasTasks.problem == nil)
    #expect(!hasTasks.refreshing)
    let attentionProjects = hasTasks.snapshot!.projects(in: .attention)
    #expect(attentionProjects.first?.hasBlocked == true)
    #expect(attentionProjects.first?.workspaces.first?.rows.first?.stateKind == .blocked)

    // 2. No pending tasks
    let noPending = InboxFixtures.noPendingState
    #expect(noPending.snapshot?.projects(in: .attention).isEmpty == true)
    #expect(noPending.snapshot?.count(in: .working) == 1)

    // 3. Refreshing
    #expect(InboxFixtures.refreshingState.refreshing)
    #expect(InboxFixtures.initialLoadingState.isInitialLoading)

    // 4. Disconnected (stale data preserved vs cold start disconnected)
    #expect(InboxFixtures.disconnectedStaleState.isDisconnectedWithStaleData)
    #expect(InboxFixtures.disconnectedStaleState.snapshot?.rows(in: .attention).isEmpty == false)
    #expect(InboxFixtures.disconnectedEmptyState.isDisconnectedWithoutData)
}

@MainActor
@Test func panelMaintainsFixedDimensionsAcrossStatesAndTabs() {
    let states: [(String, InboxPanelState, Bucket)] = [
        ("has_tasks_attention", InboxFixtures.hasTasksState, .attention),
        ("has_tasks_working", InboxFixtures.hasTasksState, .working),
        ("no_pending", InboxFixtures.noPendingState, .attention),
        ("refreshing", InboxFixtures.refreshingState, .attention),
        ("disconnected_stale", InboxFixtures.disconnectedStaleState, .attention),
        ("disconnected_empty", InboxFixtures.disconnectedEmptyState, .attention)
    ]

    for (_, state, bucket) in states {
        let view = InboxPanelView(
            state: state,
            bucket: .constant(bucket),
            onRefresh: {},
            onOpenOrca: {},
            onCopySessionID: { _ in },
            onQuit: {}
        )
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        #expect(abs(fitting.width - InboxMetrics.panelWidth) < 0.5)
        #expect(abs(fitting.height - InboxMetrics.panelHeight) < 0.5)
    }
}
