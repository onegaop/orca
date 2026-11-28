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
@Observable
private final class InboxPresentationBridge {
    var filter: InboxFeedFilter = .inbox
    var focusDispatchTrigger = 0
}

@MainActor
private final class InboxApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = InboxStore(
        fetchHosts: { try await Task.detached(priority: .utility) { try Live.fetchHosts() }.value },
        fetchSnapshot: { target in
            try await Task.detached(priority: .utility) { try Live.fetch(environment: target) }.value
        },
        fetchInstalledAgents: { target in
            try await Task.detached(priority: .utility) { try Live.fetchInstalledAgents(environment: target) }.value
        }
    )
    private let bridge = InboxPresentationBridge()
    private var statusItem: NSStatusItem?
    private var menuStatus: InboxMenuStatus?
    private var hotkeyManager: GlobalHotkeyManager?
    private var notifications: InboxNotificationCenter?
    private var pollingTask: Task<Void, Never>?
    private var menuUpdates: Task<Void, Never>?
    private var clockUpdates: Task<Void, Never>?

    private static let hubSize = NSSize(
        width: InboxMetrics.hubWidth,
        height: InboxMetrics.hubHeight
    )

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = Self.hubSize
        let controller = NSHostingController(rootView: makePopoverRootView())
        controller.preferredContentSize = Self.hubSize
        popover.contentViewController = controller
        return popover
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Item-0"
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(toggleFromMenuBar(_:))
        updateMenuButton(InboxMenuStatus(state: store.panelState()))

        let notifier = InboxNotificationCenter { [weak self] url in
            Task { await self?.openOrca(destination: url) }
        }
        notifications = notifier
        store.onAlertEvents = { [weak notifier] events in
            notifier?.post(events)
        }

        let hotkey = GlobalHotkeyManager { [weak self] in
            self?.triggerGlobalToggle()
        }
        _ = hotkey.registerOptionSpace()
        hotkeyManager = hotkey

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
        hotkeyManager?.unregister()
        pollingTask?.cancel()
        menuUpdates?.cancel()
        clockUpdates?.cancel()
    }

    private func triggerGlobalToggle() {
        bridge.focusDispatchTrigger += 1
        if let button = statusItem?.button {
            togglePopover(button)
        }
    }

    private func updateMenuButton(_ status: InboxMenuStatus) {
        guard let button = statusItem?.button else { return }
        if menuStatus?.indicator != status.indicator || menuStatus?.symbolName != status.symbolName {
            button.image = MenuBarStatusIcon.image(for: status)
        }
        if menuStatus?.text != status.text {
            button.imagePosition = status.text.isEmpty ? .imageOnly : .imageLeading
            if status.text.isEmpty {
                button.title = ""
                button.attributedTitle = NSAttributedString()
            } else {
                button.attributedTitle = NSAttributedString(
                    string: " \(status.text)",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                        .baselineOffset: 0.5
                    ]
                )
            }
        }
        if menuStatus?.description != status.description {
            button.toolTip = status.description
            button.setAccessibilityLabel("Orca 任务收件箱 · \(status.description)")
        }
        menuStatus = status
    }

    @objc private func toggleFromMenuBar(_ button: NSStatusBarButton) {
        togglePopover(button)
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
        } else {
            // Set the exact size before show so AppKit anchors the popover below the menu bar instead of resizing upward over it.
            popover.contentSize = Self.hubSize
            popover.contentViewController?.preferredContentSize = Self.hubSize
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

    private func makePopoverRootView() -> InboxHostContainer {
        InboxHostContainer(
            store: store,
            bridge: bridge,
            onOpenOrca: { [weak self] url in await self?.openOrca(destination: url) },
            onCopySessionID: copySessionID,
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    private func copySessionID(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        store.showToast("已复制会话 ID")
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
            if popover.isShown { popover.performClose(nil) }
        } catch {
            store.actionProblem = "无法打开 Orca：\(error.localizedDescription)"
        }
    }
}

@MainActor
private struct InboxHostContainer: View {
    let store: InboxStore
    let bridge: InboxPresentationBridge
    let onOpenOrca: (URL?) async -> Void
    let onCopySessionID: (String) -> Void
    let onQuit: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let state = store.panelState(at: context.date)
            let filterBinding = Binding<InboxFeedFilter>(
                get: { bridge.filter },
                set: { bridge.filter = $0 }
            )
            let handlers = makeCardHandlers(environment: state.selectedHost.id)
            InboxHubView(
                state: state,
                filter: filterBinding,
                focusDispatchTrigger: bridge.focusDispatchTrigger,
                onRefresh: { store.requestRefresh() },
                onSelectHost: { store.selectHost($0) },
                onArchiveAllDone: { store.archiveAllDone() },
                onSetNotificationsEnabled: { store.setNotificationsEnabled($0) },
                onDispatchTask: { worktreeId, agent, prompt in
                    try await dispatchTask(
                        worktreeId: worktreeId,
                        agent: agent,
                        prompt: prompt,
                        environment: state.selectedHost.id
                    )
                },
                onQuit: onQuit,
                cardHandlers: handlers
            )
        }
    }

    private func makeCardHandlers(environment: String) -> InboxCardHandlers {
        InboxCardHandlers(
            onOpenSession: { row in
                Task {
                    guard let destination = SessionDestination.url(for: row, environment: environment) else {
                        store.actionProblem = "这条记录缺少完整会话标识。可右键复制会话 ID 或打开 Orca。"
                        return
                    }
                    await onOpenOrca(destination)
                }
            },
            onCopySessionID: onCopySessionID,
            onOpenOrca: { Task { await onOpenOrca(nil) } },
            onArchive: { store.archive($0) },
            onUnarchive: { store.unarchive($0) },
            onLoadTranscript: { row in
                guard let id = row.orcaSessionId else { throw InboxFailure.unreadable }
                return try await Task.detached(priority: .userInitiated) {
                    try Live.fetchTranscript(sessionId: id, environment: environment)
                }.value
            },
            onLoadPendingPrompts: { row in
                guard let id = row.orcaSessionId else { return [] }
                return await Task.detached(priority: .userInitiated) {
                    Live.fetchPendingPrompts(sessionId: id, environment: environment)
                }.value
            },
            onReply: { row, text in
                guard let id = row.orcaSessionId else { throw InboxFailure.unreadable }
                try await Task.detached(priority: .userInitiated) {
                    try Live.replyToAgent(sessionId: id, text: text, environment: environment)
                }.value
                store.showToast("已发送回复给「\(row.label)」")
                store.requestRefresh()
            },
            onRespondPrompt: { row, prompt, option in
                guard let id = row.orcaSessionId else { throw InboxFailure.unreadable }
                try await Task.detached(priority: .userInitiated) {
                    try Live.respondToPrompt(sessionId: id, prompt: prompt, option: option, environment: environment)
                }.value
                store.showToast("已确认「\(option.label)」")
                store.requestRefresh()
            }
        )
    }

    private func dispatchTask(
        worktreeId: String,
        agent: String,
        prompt: String,
        environment: String
    ) async throws {
        store.rememberDispatchSelection(worktreeId: worktreeId, agent: agent)
        try await Task.detached(priority: .userInitiated) {
            try Live.dispatchAgent(worktreeId: worktreeId, agent: agent, prompt: prompt, environment: environment)
        }.value
        store.showToast("已派发给 \(agent) 后台运行")
        store.requestRefresh()
    }
}
