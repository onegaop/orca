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
    public private(set) var hosts: [HostTarget]
    public private(set) var selectedHost: HostTarget
    public private(set) var panelIsOpen = false
    public var actionProblem: String?
    private var cache: [String: CachedHost] = [:]
    private var refreshingHost: String?
    private var selectionNeedsRefresh = true
    private var refreshRequested = true
    private var polling = false
    private var sleepTask: Task<Void, Never>?
    private let fetchHosts: @Sendable () async throws -> [HostTarget]
    private let fetchSnapshot: @Sendable (String) async throws -> Snapshot
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        fetchHosts: @escaping @Sendable () async throws -> [HostTarget],
        fetchSnapshot: @escaping @Sendable (String) async throws -> Snapshot
    ) {
        self.defaults = defaults
        self.fetchHosts = fetchHosts
        self.fetchSnapshot = fetchSnapshot
        let saved = defaults.string(forKey: Self.selectedHostKey) ?? "local"
        let selected = saved.isEmpty || saved == "local"
            ? HostTarget.local : HostTarget(id: saved, name: saved, isLocal: false)
        selectedHost = selected
        hosts = selected.isLocal ? [.local] : [.local, selected]
    }

    public var snapshot: Snapshot? { cache[selectedHost.id]?.snapshot }
    public var updated: Date? { cache[selectedHost.id]?.updated }
    public var problem: String? { cache[selectedHost.id]?.problem }
    public var refreshing: Bool { refreshingHost == selectedHost.id || refreshRequested }

    public func panelState(at now: Date = .now) -> InboxPanelState {
        InboxPanelState(
            snapshot: snapshot, updated: updated, problem: problem, refreshing: refreshing,
            referenceDate: now, hosts: hosts, selectedHost: selectedHost,
            stale: selectionNeedsRefresh || updated.map { now.timeIntervalSince($0) > 120 } == true,
            actionProblem: actionProblem
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
            let delay = panelIsOpen ? 15 : 60
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
        if Task.isCancelled { return }
        do {
            let fetched = try await fetchSnapshot(target)
            if Task.isCancelled { return }
            cache[target] = CachedHost(snapshot: fetched, updated: .now, problem: nil)
            if target == selectedHost.id { selectionNeedsRefresh = false }
        } catch {
            if Task.isCancelled { return }
            var previous = cache[target] ?? CachedHost()
            previous.problem = error.localizedDescription
            cache[target] = previous
        }
    }
}
