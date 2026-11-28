import Foundation
import Observation

@MainActor
@Observable
public final class InboxStore {
    private struct CachedHost {
        var snapshot: Snapshot?
        var updated: Date?
        var problem: String?
    }

    private static let selectedHostKey = "orcaInbox.selectedHostId"
    private static let archivedTimestampsKey = "orcaInbox.archivedTimestamps"
    private static let presentationModeKey = "orcaInbox.presentationMode"
    private static let notificationsEnabledKey = "orcaInbox.notificationsEnabled"
    private static let dispatchWorktreeKey = "orcaInbox.lastDispatchWorktreeId"
    private static let dispatchAgentKey = "orcaInbox.lastDispatchAgent"

    public private(set) var hosts: [HostTarget]
    public private(set) var selectedHost: HostTarget
    public private(set) var panelIsOpen = false
    public private(set) var archivedTimestamps: [String: Double]
    public private(set) var presentationMode: InboxPresentationMode
    public private(set) var notificationsEnabled: Bool
    public private(set) var installedAgents: [InstalledAgentOption] = InstalledAgentOption.defaults
    public private(set) var defaultDispatchWorktreeId: String?
    public private(set) var defaultDispatchAgent: String
    public var actionProblem: String?
    public var toastMessage: String?
    public var onAlertEvents: (([InboxAlertEvent]) -> Void)?

    private var cache: [String: CachedHost] = [:]
    private var refreshingHost: String?
    private var selectionNeedsRefresh = true
    private var refreshRequested = true
    private var polling = false
    private var sleepTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var loadedAgentsForHost: String?
    private let fetchHosts: @Sendable () async throws -> [HostTarget]
    private let fetchSnapshot: @Sendable (String) async throws -> Snapshot
    private let fetchInstalledAgents: (@Sendable (String) async throws -> [InstalledAgentOption])?
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        fetchHosts: @escaping @Sendable () async throws -> [HostTarget],
        fetchSnapshot: @escaping @Sendable (String) async throws -> Snapshot,
        fetchInstalledAgents: (@Sendable (String) async throws -> [InstalledAgentOption])? = nil
    ) {
        self.defaults = defaults
        self.fetchHosts = fetchHosts
        self.fetchSnapshot = fetchSnapshot
        self.fetchInstalledAgents = fetchInstalledAgents
        let saved = defaults.string(forKey: Self.selectedHostKey) ?? "local"
        let selected = saved.isEmpty || saved == "local"
            ? HostTarget.local : HostTarget(id: saved, name: saved, isLocal: false)
        selectedHost = selected
        hosts = selected.isLocal ? [.local] : [.local, selected]

        if let rawArchived = defaults.dictionary(forKey: Self.archivedTimestampsKey) as? [String: Double] {
            archivedTimestamps = rawArchived
        } else {
            archivedTimestamps = [:]
        }
        if let rawMode = defaults.string(forKey: Self.presentationModeKey),
           let mode = InboxPresentationMode(rawValue: rawMode) {
            presentationMode = mode
        } else {
            presentationMode = .notch
        }
        if defaults.object(forKey: Self.notificationsEnabledKey) != nil {
            notificationsEnabled = defaults.bool(forKey: Self.notificationsEnabledKey)
        } else {
            notificationsEnabled = true
        }
        defaultDispatchWorktreeId = defaults.string(forKey: Self.dispatchWorktreeKey)
        defaultDispatchAgent = defaults.string(forKey: Self.dispatchAgentKey) ?? "codex"
    }

    public var snapshot: Snapshot? { cache[selectedHost.id]?.snapshot }
    public var updated: Date? { cache[selectedHost.id]?.updated }
    public var problem: String? { cache[selectedHost.id]?.problem }
    public var refreshing: Bool { refreshingHost == selectedHost.id || refreshRequested }

    public func panelState(at now: Date = .now) -> InboxPanelState {
        let workspaces = snapshot.map(DispatchWorkspaceOption.fromSnapshot) ?? []
        return InboxPanelState(
            snapshot: snapshot,
            updated: updated,
            problem: problem,
            refreshing: refreshing,
            referenceDate: now,
            hosts: hosts,
            selectedHost: selectedHost,
            stale: selectionNeedsRefresh || updated.map { now.timeIntervalSince($0) > 120 } == true,
            actionProblem: actionProblem,
            archivedTimestamps: archivedTimestamps,
            presentationMode: presentationMode,
            notificationsEnabled: notificationsEnabled,
            dispatchWorkspaces: workspaces,
            installedAgents: installedAgents,
            defaultDispatchWorktreeId: defaultDispatchWorktreeId ?? workspaces.first?.worktreeId,
            defaultDispatchAgent: defaultDispatchAgent,
            toastMessage: toastMessage
        )
    }

    public func selectHost(_ host: HostTarget) {
        guard host.id != selectedHost.id else { return }
        selectedHost = host
        defaults.set(host.id, forKey: Self.selectedHostKey)
        selectionNeedsRefresh = true
        actionProblem = nil
        requestRefresh()
    }

    public func setPresentationMode(_ mode: InboxPresentationMode) {
        guard presentationMode != mode else { return }
        presentationMode = mode
        defaults.set(mode.rawValue, forKey: Self.presentationModeKey)
    }

    public func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: Self.notificationsEnabledKey)
    }

    public func rememberDispatchSelection(worktreeId: String, agent: String) {
        defaultDispatchWorktreeId = worktreeId
        defaultDispatchAgent = agent
        defaults.set(worktreeId, forKey: Self.dispatchWorktreeKey)
        defaults.set(agent, forKey: Self.dispatchAgentKey)
    }

    public func archive(_ row: AgentRow) {
        guard row.stateKind == .done else { return }
        archivedTimestamps[row.id] = max(row.updatedAt, archivedTimestamps[row.id] ?? 0)
        persistArchived()
        showToast("已归档「\(row.label)」")
    }

    public func unarchive(_ row: AgentRow) {
        archivedTimestamps.removeValue(forKey: row.id)
        persistArchived()
    }

    public func archiveAllDone() {
        guard let snapshot else { return }
        var changed = 0
        for row in snapshot.agents where InboxTriageRules.isUnreadDone(row, archivedTimestamps: archivedTimestamps) {
            archivedTimestamps[row.id] = max(row.updatedAt, archivedTimestamps[row.id] ?? 0)
            changed += 1
        }
        guard changed > 0 else { return }
        persistArchived()
        showToast("已归档 \(changed) 条已完成任务")
    }

    public func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    public func setPanelOpen(_ open: Bool) {
        panelIsOpen = open
        if open { requestRefresh() }
    }

    public func requestRefresh() {
        if refreshingHost != selectedHost.id { refreshRequested = true }
        sleepTask?.cancel()
    }

    public func runPolling() async {
        guard !polling else { return }
        polling = true
        defer {
            polling = false
            refreshingHost = nil
            sleepTask?.cancel()
            sleepTask = nil
        }
        while !Task.isCancelled {
            refreshRequested = false
            await refreshSelectedHost()
            if refreshRequested { continue }
            // Responsive 3s cadence while open; lightweight 10s cadence when collapsed so alerts arrive promptly.
            let delay = panelIsOpen ? 3 : 10
            let sleeper = Task<Void, Never> { try? await Task.sleep(for: .seconds(delay)) }
            sleepTask = sleeper
            await withTaskCancellationHandler {
                await sleeper.value
            } onCancel: {
                sleeper.cancel()
            }
            sleepTask = nil
        }
    }

    func refreshSelectedHost() async {
        guard refreshingHost == nil else { return }
        let target = selectedHost.id
        refreshingHost = target
        defer { refreshingHost = nil }
        if let discovered = try? await fetchHosts(), !discovered.isEmpty {
            hosts = discovered
            if let match = discovered.first(where: { $0.id == selectedHost.id }) {
                selectedHost = match
            } else {
                // A temporarily unavailable selected environment must never become local.
                hosts.append(selectedHost)
            }
        }
        if let fetchInstalledAgents, loadedAgentsForHost != target {
            if let agents = try? await fetchInstalledAgents(target), !agents.isEmpty {
                installedAgents = agents
                loadedAgentsForHost = target
                if !agents.contains(where: { $0.id == defaultDispatchAgent }) {
                    defaultDispatchAgent = agents[0].id
                }
            }
        }
        if Task.isCancelled { return }
        do {
            let previousSnapshot = cache[target]?.snapshot
            let fetched = try await fetchSnapshot(target)
            if Task.isCancelled { return }
            cache[target] = CachedHost(snapshot: fetched, updated: .now, problem: nil)
            if target == selectedHost.id { selectionNeedsRefresh = false }
            if notificationsEnabled, let onAlertEvents {
                let events = InboxTransitionDetector.detect(
                    previous: previousSnapshot,
                    next: fetched,
                    environment: target
                )
                if !events.isEmpty {
                    onAlertEvents(events)
                }
            }
        } catch {
            if Task.isCancelled { return }
            var previous = cache[target] ?? CachedHost()
            previous.problem = error.localizedDescription
            cache[target] = previous
        }
    }

    private func persistArchived() {
        // Bound persisted archive map to the 200 newest entries so UserDefaults stays tiny.
        if archivedTimestamps.count > 200 {
            let kept = archivedTimestamps.sorted { $0.value > $1.value }.prefix(200)
            archivedTimestamps = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        defaults.set(archivedTimestamps, forKey: Self.archivedTimestampsKey)
    }
}
