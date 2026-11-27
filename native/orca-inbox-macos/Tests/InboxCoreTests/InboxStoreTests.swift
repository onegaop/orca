import Foundation
import Testing
@testable import InboxCore

private actor SuspendedFetch {
    private var continuation: CheckedContinuation<Snapshot, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch() async -> Snapshot {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func complete() {
        continuation?.resume(returning: Snapshot(agents: []))
        continuation = nil
    }
}

@MainActor
@Test func inFlightHostSwitchNeverShowsAnotherHostsResultOrFalseZero() async throws {
    let suite = "orca-inbox-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let suspended = SuspendedFetch()
    let remote = HostTarget(id: "env-mini", name: "Mini", isLocal: false)
    let store = InboxStore(defaults: defaults, fetchHosts: { [.local] }, fetchSnapshot: { target in
        if target == "local" { return await suspended.fetch() }
        throw InboxFailure.timeout
    })
    let inFlight = Task { await store.refreshSelectedHost() }
    await suspended.waitUntilStarted()
    store.selectHost(remote)
    #expect(store.snapshot == nil)
    #expect(InboxMenuStatus(state: store.panelState()).text == "…")
    await suspended.complete()
    await inFlight.value
    #expect(store.selectedHost.id == "env-mini")
    #expect(store.snapshot == nil)
    await store.refreshSelectedHost()
    #expect(store.selectedHost.id == "env-mini")
    #expect(store.hosts.contains(remote))
    #expect(store.snapshot == nil)
    #expect(InboxMenuStatus(state: store.panelState()).text == "!")
    store.selectHost(.local)
    #expect(store.snapshot != nil)
    #expect(InboxMenuStatus(state: store.panelState()).text == "0~")
}
