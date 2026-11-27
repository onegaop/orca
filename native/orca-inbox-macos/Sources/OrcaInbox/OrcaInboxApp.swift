import SwiftUI
import AppKit
import InboxCore
import InboxUI
import Darwin

@main
struct OrcaInboxApp: App {
    init() {
        if CommandLine.arguments.contains("--check-live") {
            do {
                let hosts = try Live.fetchHosts()
                let envIndex = CommandLine.arguments.firstIndex(of: "--environment")
                let env = envIndex.flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil } ?? "local"
                let snapshot = try Live.fetch(environment: env)
                print("OK env=\(env) hosts=\(hosts.map(\.displayName).joined(separator: ",")) agents=\(snapshot.agents.count) truncated=\(snapshot.truncated)")
                exit(EXIT_SUCCESS)
            } catch {
                print("ERROR: \(error.localizedDescription)")
                exit(EXIT_FAILURE)
            }
        }
    }

    @State private var store = InboxStore(
        fetchHosts: { try await Task.detached(priority: .utility) { try Live.fetchHosts() }.value },
        fetchSnapshot: { target in
            try await Task.detached(priority: .utility) { try Live.fetch(environment: target) }.value
        }
    )

    var body: some Scene {
        MenuBarExtra {
            InboxWindow(store: store)
        } label: {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let status = InboxMenuStatus(state: store.panelState(at: context.date))
                Label(status.text, systemImage: status.symbolName)
                    .monospacedDigit()
                    .help(status.description)
                    .accessibilityLabel("Orca 任务收件箱 · \(status.description)")
            }
            .task { await store.runPolling() }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private struct InboxWindow: View {
    let store: InboxStore
    @State private var bucket: Bucket = .attention

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let state = store.panelState(at: context.date)
            InboxPanelView(
                state: state,
                bucket: $bucket,
                onRefresh: { store.requestRefresh() },
                onSelectHost: { store.selectHost($0) },
                onOpenOrca: { Task { await openOrca() } },
                onOpenSession: { row in Task { await openSession(row, environment: state.selectedHost.id) } },
                onCopySessionID: copySessionID,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .onAppear { store.setPanelOpen(true) }
        .onDisappear { store.setPanelOpen(false) }
    }

    private func copySessionID(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    private func openSession(_ row: AgentRow, environment: String) async {
        guard let destination = SessionDestination.url(for: row, environment: environment) else {
            store.actionProblem = "这条记录缺少完整会话标识。可右键复制会话 ID 或打开 Orca。"
            return
        }
        await openOrca(destination: destination)
    }

    private func openOrca(destination: URL? = nil) async {
        store.actionProblem = nil
        guard let appURL = Live.resolveAppURL() else {
            store.actionProblem = InboxFailure.missingCLI.localizedDescription
            return
        }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            if let destination {
                _ = try await NSWorkspace.shared.open(
                    [destination], withApplicationAt: appURL, configuration: configuration
                )
            } else {
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
        } catch {
            store.actionProblem = "无法打开 Orca：\(error.localizedDescription)"
        }
    }
}
