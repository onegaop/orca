import Foundation
import AppKit
import SwiftUI
import Testing
@testable import InboxCore
@testable import InboxUI

@Test func summaryPreviewStripsMarkdownNoiseAndCapsLength() {
    let row = AgentRow(
        kind: "chat",
        agent: "codex",
        state: "done",
        worktreeId: "r::w",
        workspace: "main",
        repo: "orca",
        paneKey: "p1",
        title: "升级 LuCI",
        lastAssistantMessage: "## **LuCI 已更新完成。** 查看 [文档](https://example.com) 并验证 `tailscale status`。\n\n一切正常。",
        updatedAt: 10_000
    )
    #expect(row.summaryPreview == "LuCI 已更新完成。 查看 文档 并验证 tailscale status。 一切正常。")
    #expect(row.contextTag == "orca · codex")
    #expect(row.isChat)
}

@Test func triageArchiveHidesDoneUntilNewTurnAndNeverHidesUrgent() {
    let blocked = AgentRow(state: "blocked", worktreeId: "r::1", workspace: "main", paneKey: "p1", updatedAt: 1_000)
    let waiting = AgentRow(state: "waiting", worktreeId: "r::2", workspace: "main", paneKey: "p2", updatedAt: 2_000)
    let doneOld = AgentRow(state: "done", worktreeId: "r::3", workspace: "main", paneKey: "p3", updatedAt: 3_000)
    let doneNew = AgentRow(state: "done", worktreeId: "r::4", workspace: "main", paneKey: "p4", updatedAt: 5_000)
    let working = AgentRow(state: "working", worktreeId: "r::5", workspace: "main", paneKey: "p5", updatedAt: 4_000)
    let snapshot = Snapshot(agents: [doneOld, working, waiting, blocked, doneNew])

    // Even if blocked/waiting ids exist in archived map, urgent items must never be archived.
    let archived: [String: Double] = [
        blocked.id: 9_999,
        waiting.id: 9_999,
        doneOld.id: 3_000, // archived at exact updatedAt -> hidden from .inbox
        doneNew.id: 4_000  // newer turn arrived (5000 > 4000) -> resurfaces in .inbox
    ]

    let inboxRows = InboxTriageRules.filteredRows(snapshot: snapshot, filter: .inbox, archivedTimestamps: archived)
    #expect(inboxRows.map(\.paneKey) == ["p1", "p2", "p4"])

    let counts = InboxTriageRules.counts(snapshot: snapshot, archivedTimestamps: archived)
    #expect(counts.blocked == 1)
    #expect(counts.waiting == 1)
    #expect(counts.urgent == 2)
    #expect(counts.unreadDone == 1)
    #expect(counts.inbox == 3)
    #expect(counts.working == 1)
    #expect(counts.total == 5)
}

@Test func transitionDetectorSkipsColdLoadAndEmitsStateTransitions() {
    let w1 = AgentRow(orcaSessionId: "session_01", state: "working", worktreeId: "r::1", workspace: "main", paneKey: "tab-1:12345678-1234-4234-9234-123456789abc", title: "编译任务", updatedAt: 1000)
    let coldEvents = InboxTransitionDetector.detect(previous: nil, next: Snapshot(agents: [w1]), environment: "local")
    #expect(coldEvents.isEmpty)

    let done1 = AgentRow(orcaSessionId: "session_01", state: "done", worktreeId: "r::1", workspace: "main", paneKey: "tab-1:12345678-1234-4234-9234-123456789abc", title: "编译任务", lastAssistantMessage: "全部通过", updatedAt: 2000)
    let blocked2 = AgentRow(orcaSessionId: "session_02", state: "blocked", worktreeId: "r::2", workspace: "main", paneKey: "tab-2:12345678-1234-4234-9234-123456789abc", title: "发布审批", updatedAt: 2100)
    let events = InboxTransitionDetector.detect(
        previous: Snapshot(agents: [w1]),
        next: Snapshot(agents: [done1, blocked2]),
        environment: "local"
    )
    #expect(events.count == 2)
    #expect(events.contains(where: { $0.kind == .done && $0.body == "全部通过" }))
    #expect(events.contains(where: { $0.kind == .blocked && $0.title.contains("发布审批") }))
}

@Test func decodeTranscriptAndPendingPromptsRoundTrip() throws {
    let transcriptJSON = Data("""
    {"ok":true,"result":{"state":"waiting","limited":false,"entries":[
      {"kind":"message","role":"user","text":"检查一下构建"},
      {"kind":"message","role":"assistant","text":"需要执行 git push","tools":[{"name":"run_command","state":"running"}]},
      {"kind":"approval","text":"git push origin main","pending":true}
    ]}}
    """.utf8)
    let page = try decodeTranscriptPage(transcriptJSON)
    #expect(page.state == "waiting")
    #expect(page.entries.count == 3)
    #expect(page.entries[1].tools.first?.name == "run_command")
    #expect(page.entries[2].pending)

    let promptsJSON = Data("""
    {"ok":true,"result":{"orcaSessionId":"s1","prompts":[
      {"itemId":"item_9","revision":2,"kind":"approval","title":"Run shell command","detail":"git push origin main","options":[
        {"id":"allow_once","label":"允许一次","kind":"allow"},
        {"id":"reject_once","label":"拒绝","kind":"reject"}
      ]}
    ]}}
    """.utf8)
    let prompts = decodePendingPrompts(promptsJSON)
    #expect(prompts.count == 1)
    #expect(prompts[0].itemId == "item_9")
    #expect(prompts[0].options.count == 2)
}

@Test func menuBarStatusReflectsHighestPriorityIndicator() {
    let blocked = AgentRow(state: "blocked", worktreeId: "r::1", workspace: "main", paneKey: "p1", updatedAt: 1000)
    let waiting = AgentRow(state: "waiting", worktreeId: "r::2", workspace: "main", paneKey: "p2", updatedAt: 2000)
    let done = AgentRow(state: "done", worktreeId: "r::3", workspace: "main", paneKey: "p3", updatedAt: 3000)
    let working = AgentRow(state: "working", worktreeId: "r::4", workspace: "main", paneKey: "p4", updatedAt: 4000)

    let blockedStatus = InboxMenuStatus(state: InboxPanelState(snapshot: Snapshot(agents: [blocked, waiting, working])))
    #expect(blockedStatus.indicator == .blocked)
    #expect(blockedStatus.text == "2")
    #expect(blockedStatus.description.contains("1 项阻塞"))

    let waitingStatus = InboxMenuStatus(state: InboxPanelState(snapshot: Snapshot(agents: [waiting, done])))
    #expect(waitingStatus.indicator == .waiting)
    #expect(waitingStatus.text == "1")

    let doneStatus = InboxMenuStatus(state: InboxPanelState(snapshot: Snapshot(agents: [done, working])))
    #expect(doneStatus.indicator == .unreadDone)
    #expect(doneStatus.text == "1")

    // Once done is archived, indicator falls through to working.
    let workingStatus = InboxMenuStatus(
        state: InboxPanelState(snapshot: Snapshot(agents: [done, working]), archivedTimestamps: [done.id: 3000])
    )
    #expect(workingStatus.indicator == .working)
    #expect(workingStatus.symbolName == "waveform")
    #expect(workingStatus.text == "1")

    // When all clear and healthy, menu bar stays quiet with empty text.
    let idleStatus = InboxMenuStatus(
        state: InboxPanelState(snapshot: Snapshot(agents: [done]), archivedTimestamps: [done.id: 3000])
    )
    #expect(idleStatus.indicator == .idle)
    #expect(idleStatus.text == "")

    let staleStatus = InboxMenuStatus(state: InboxPanelState(snapshot: Snapshot(agents: []), stale: true))
    #expect(staleStatus.indicator == .stale)
    #expect(staleStatus.text == "0~")

    let disconnectedStatus = InboxMenuStatus(state: InboxPanelState(problem: "offline"))
    #expect(disconnectedStatus.indicator == .disconnected)
    #expect(disconnectedStatus.text == "!")

    let loadingStatus = InboxMenuStatus(state: InboxPanelState())
    #expect(loadingStatus.indicator == .loading)
    #expect(loadingStatus.text == "…")
}

@MainActor
@Test func hubViewKeepsExpectedDimensions() {
    let hub = InboxHubView(
        state: InboxFixtures.hasTasksState,
        filter: .constant(.inbox),
        onRefresh: {},
        onQuit: {},
        cardHandlers: InboxCardHandlers()
    )
    let hubHosting = NSHostingView(rootView: hub)
    #expect(abs(hubHosting.fittingSize.width - InboxMetrics.hubWidth) < 1)
    #expect(abs(hubHosting.fittingSize.height - InboxMetrics.hubHeight) < 1)
}
