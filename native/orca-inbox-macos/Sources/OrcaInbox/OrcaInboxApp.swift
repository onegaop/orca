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
                let hosts = Live.fetchHosts()
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
    private static let selectedHostKey = "orcaInbox.selectedHostId"

    var hosts: [HostTarget] = [.local]
    var selectedHost: HostTarget = .local
    var snapshot: Snapshot?
    var updated: Date?
    var problem: String?
    var refreshing = false

    private var snapshotsByHost: [String: (snapshot: Snapshot, updated: Date)] = [:]
    private var requestToken = 0

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.selectedHostKey), !saved.isEmpty {
            if saved != "local" {
                selectedHost = HostTarget(id: saved, name: saved, isLocal: false)
            }
        }
    }

    func selectHost(_ host: HostTarget) {
        guard host.id != selectedHost.id else { return }
        selectedHost = host
        UserDefaults.standard.set(host.id, forKey: Self.selectedHostKey)
        if let cached = snapshotsByHost[host.id] {
            snapshot = cached.snapshot
            updated = cached.updated
        } else {
            snapshot = nil
            updated = nil
        }
        problem = nil
        Task { await refresh(force: true) }
    }

    func refresh(force: Bool = false) async {
        if refreshing && !force { return }
        requestToken += 1
        let token = requestToken
        refreshing = true
        defer {
            if token == requestToken {
                refreshing = false
            }
        }

        let discovered = await Task.detached(priority: .utility) { Live.fetchHosts() }.value
        guard token == requestToken else { return }
        hosts = discovered
        if let matched = discovered.first(where: { $0.id == selectedHost.id }) {
            selectedHost = matched
        } else {
            selectedHost = discovered.first ?? .local
            UserDefaults.standard.set(selectedHost.id, forKey: Self.selectedHostKey)
        }

        let targetId = selectedHost.id
        do {
            let fetched = try await Task.detached(priority: .utility) {
                try Live.fetch(environment: targetId)
            }.value
            guard token == requestToken, targetId == selectedHost.id else { return }
            let now = Date.now
            snapshotsByHost[targetId] = (fetched, now)
            snapshot = fetched
            updated = now
            problem = nil
        } catch {
            guard token == requestToken, targetId == selectedHost.id else { return }
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
                    referenceDate: context.date,
                    hosts: store.hosts,
                    selectedHost: store.selectedHost
                ),
                bucket: $bucket,
                onRefresh: { Task { await store.refresh() } },
                onSelectHost: { store.selectHost($0) },
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
        guard let url = Live.resolveAppURL() else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
