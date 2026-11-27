import SwiftUI
import AppKit
import InboxCore
import InboxUI
import Observation
import Darwin

@main
@MainActor
enum OrcaInboxApp {
    static func main() {
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

        let application = NSApplication.shared
        let delegate = InboxApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class InboxApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = InboxStore(
        fetchHosts: { try await Task.detached(priority: .utility) { try Live.fetchHosts() }.value },
        fetchSnapshot: { target in
            try await Task.detached(priority: .utility) { try Live.fetch(environment: target) }.value
        }
    )
    private var statusItem: NSStatusItem?
    private var menuStatus: InboxMenuStatus?
    private var pollingTask: Task<Void, Never>?
    private var menuUpdates: Task<Void, Never>?
    private var clockUpdates: Task<Void, Never>?

    private static let panelSize = NSSize(
        width: InboxMetrics.panelWidth,
        height: InboxMetrics.panelHeight
    )

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = Self.panelSize
        let controller = NSHostingController(rootView: InboxWindow(store: store))
        controller.preferredContentSize = Self.panelSize
        popover.contentViewController = controller
        return popover
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Item-0"
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.imagePosition = .imageLeading
        updateMenuButton(InboxMenuStatus(state: store.panelState()))

        menuUpdates = Task { [weak self, store] in
            for await status in Observations({ InboxMenuStatus(state: store.panelState()) }) {
                self?.updateMenuButton(status)
            }
        }
        clockUpdates = Task { [weak self, store] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                self?.updateMenuButton(InboxMenuStatus(state: store.panelState()))
            }
        }
        pollingTask = Task { [store] in await store.runPolling() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
        menuUpdates?.cancel()
        clockUpdates?.cancel()
    }

    private func updateMenuButton(_ status: InboxMenuStatus) {
        guard let button = statusItem?.button else { return }
        if menuStatus?.symbolName != status.symbolName {
            let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
        }
        if menuStatus?.text != status.text { button.title = status.text }
        if menuStatus?.description != status.description {
            button.toolTip = status.description
            button.setAccessibilityLabel("Orca 任务收件箱 · \(status.description)")
        }
        menuStatus = status
    }

    @objc private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
        } else {
            // Set the exact size before show so AppKit anchors the popover below the menu bar instead of resizing upward over it.
            popover.contentSize = Self.panelSize
            popover.contentViewController?.preferredContentSize = Self.panelSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        store.setPanelOpen(true)
    }

    func popoverWillClose(_ notification: Notification) {
        store.setPanelOpen(false)
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
