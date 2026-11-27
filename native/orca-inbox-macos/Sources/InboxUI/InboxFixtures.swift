import Foundation
import InboxCore

/// Purely fictional datasets used for SwiftUI previews, tests, and visual verification.
/// Never reads real workspaces, tasks, or Orca sessions.
public enum InboxFixtures {
    public static let referenceDate = Date(timeIntervalSince1970: 1_795_788_000) // 2026-11-27 22:00:00 +0800

    private static func msAgo(minutes: Double) -> Double {
        (referenceDate.timeIntervalSince1970 - minutes * 60) * 1000
    }

    public static var populatedSnapshot: Snapshot {
        Snapshot(
            agents: [
                // Project 1: Very long project name with both blocked and waiting tasks across two workspaces
                AgentRow(
                    orcaSessionId: "demo-session-01",
                    agent: "Claude",
                    state: "blocked",
                    worktreeId: "demo-repo-alpha::/demo/payment-gateway/fix-idempotency",
                    workspace: "fix/settlement-idempotency-retry-queue",
                    repo: "enterprise-global-settlement-gateway-monorepo",
                    hostId: "mini",
                    paneKey: "pane-1",
                    title: "需要确认跨境退款幂等键的数据库唯一索引方案",
                    updatedAt: msAgo(minutes: 3)
                ),
                AgentRow(
                    orcaSessionId: "demo-session-02",
                    agent: "Codex",
                    state: "waiting",
                    worktreeId: "demo-repo-alpha::/demo/payment-gateway/fix-idempotency",
                    workspace: "fix/settlement-idempotency-retry-queue",
                    repo: "enterprise-global-settlement-gateway-monorepo",
                    hostId: "mini",
                    paneKey: "pane-2",
                    title: "补齐异常账单重试单测并等待验收",
                    updatedAt: msAgo(minutes: 14)
                ),
                AgentRow(
                    orcaSessionId: "demo-session-03",
                    agent: "Gemini",
                    state: "waiting",
                    worktreeId: "demo-repo-alpha::/demo/payment-gateway/main",
                    workspace: "main",
                    repo: "enterprise-global-settlement-gateway-monorepo",
                    hostId: "mini",
                    paneKey: "pane-3",
                    title: "发布脚本版本检查待确认",
                    updatedAt: msAgo(minutes: 42)
                ),
                // Project 2: Normal name with one waiting task (missing title to verify no duplicate agent subtitle)
                AgentRow(
                    orcaSessionId: "demo-session-04",
                    agent: "Claude",
                    state: "waiting",
                    worktreeId: "demo-repo-beta::/demo/design-tokens/v3",
                    workspace: "feat/dark-mode-contrast",
                    repo: "aurora-design-kit",
                    hostId: "mini",
                    paneKey: "pane-4",
                    title: nil,
                    updatedAt: msAgo(minutes: 130)
                ),
                // Working tasks
                AgentRow(
                    orcaSessionId: "demo-session-05",
                    agent: "Codex",
                    state: "working",
                    worktreeId: "demo-repo-alpha::/demo/payment-gateway/main",
                    workspace: "main",
                    repo: "enterprise-global-settlement-gateway-monorepo",
                    hostId: "mini",
                    paneKey: "pane-5",
                    title: "生成 OpenAPI 变更摘要与契约校验",
                    updatedAt: msAgo(minutes: 1)
                ),
                AgentRow(
                    orcaSessionId: "demo-session-06",
                    agent: "Gemini",
                    state: "working",
                    worktreeId: "demo-repo-gamma::/demo/docs/guides",
                    workspace: "docs/migration-guide",
                    repo: "atlas-handbook",
                    hostId: "mini",
                    paneKey: "pane-6",
                    title: "整理迁移清单中的 Breaking Changes",
                    updatedAt: msAgo(minutes: 8)
                ),
                // Done tasks
                AgentRow(
                    orcaSessionId: "demo-session-07",
                    agent: "Claude",
                    state: "done",
                    worktreeId: "demo-repo-beta::/demo/design-tokens/v3",
                    workspace: "feat/dark-mode-contrast",
                    repo: "aurora-design-kit",
                    hostId: "mini",
                    paneKey: "pane-7",
                    title: "校准高对比度语义色表",
                    updatedAt: msAgo(minutes: 195)
                )
            ],
            truncated: false
        )
    }

    public static var emptyAttentionSnapshot: Snapshot {
        Snapshot(
            agents: [
                AgentRow(
                    orcaSessionId: "demo-session-11",
                    agent: "Codex",
                    state: "working",
                    worktreeId: "demo-repo-gamma::/demo/docs/guides",
                    workspace: "main",
                    repo: "atlas-handbook",
                    hostId: "mini",
                    paneKey: "pane-11",
                    title: "更新接口示例与回归测试",
                    updatedAt: msAgo(minutes: 2)
                ),
                AgentRow(
                    orcaSessionId: "demo-session-12",
                    agent: "Claude",
                    state: "done",
                    worktreeId: "demo-repo-beta::/demo/design-tokens/v3",
                    workspace: "main",
                    repo: "aurora-design-kit",
                    hostId: "mini",
                    paneKey: "pane-12",
                    title: "清理旧图标资源",
                    updatedAt: msAgo(minutes: 50)
                )
            ],
            truncated: false
        )
    }

    public static var hasTasksState: InboxPanelState {
        InboxPanelState(
            snapshot: populatedSnapshot,
            updated: referenceDate,
            problem: nil,
            refreshing: false,
            referenceDate: referenceDate
        )
    }

    public static var noPendingState: InboxPanelState {
        InboxPanelState(
            snapshot: emptyAttentionSnapshot,
            updated: referenceDate,
            problem: nil,
            refreshing: false,
            referenceDate: referenceDate
        )
    }

    public static var refreshingState: InboxPanelState {
        InboxPanelState(
            snapshot: populatedSnapshot,
            updated: referenceDate.addingTimeInterval(-45),
            problem: nil,
            refreshing: true,
            referenceDate: referenceDate
        )
    }

    public static var initialLoadingState: InboxPanelState {
        InboxPanelState(
            snapshot: nil,
            updated: nil,
            problem: nil,
            refreshing: true,
            referenceDate: referenceDate
        )
    }

    public static var disconnectedStaleState: InboxPanelState {
        InboxPanelState(
            snapshot: populatedSnapshot,
            updated: referenceDate.addingTimeInterval(-360),
            problem: InboxFailure.rejected("daemon_offline").localizedDescription,
            refreshing: false,
            referenceDate: referenceDate
        )
    }

    public static var disconnectedEmptyState: InboxPanelState {
        InboxPanelState(
            snapshot: nil,
            updated: nil,
            problem: InboxFailure.rejected("daemon_offline").localizedDescription,
            refreshing: false,
            referenceDate: referenceDate
        )
    }
}
