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
                let snapshot = try Live.fetch()
                print("OK agents=\(snapshot.agents.count) truncated=\(snapshot.truncated)")
                exit(EXIT_SUCCESS)
            } catch {
                print("ERROR: \(error.localizedDescription)")
                exit(EXIT_FAILURE)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            InboxWindow()
        } label: {
            Label("Orca 任务收件箱", systemImage: "tray")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
private final class InboxStore {
    var snapshot: Snapshot?
    var updated: Date?
    var problem: String?
    var refreshing = false

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            snapshot = try await Task.detached(priority: .utility) { try Live.fetch() }.value
            updated = .now
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

@MainActor
private struct InboxWindow: View {
    @State private var store = InboxStore()
    @State private var bucket: Bucket = .attention

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            InboxPanelView(
                state: InboxPanelState(
                    snapshot: store.snapshot,
                    updated: store.updated,
                    problem: store.problem,
                    refreshing: store.refreshing,
                    referenceDate: context.date
                ),
                bucket: $bucket,
                onRefresh: { Task { await store.refresh() } },
                onOpenOrca: openOrca,
                onCopySessionID: copySessionID,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .task {
            // Read only while the popover is open, stop periodic polling after it closes.
            while !Task.isCancelled {
                await store.refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            }
        }
    }

    private func copySessionID(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    private func openOrca() {
        NSWorkspace.shared.openApplication(at: Live.appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
