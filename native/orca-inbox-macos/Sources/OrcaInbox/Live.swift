import AppKit
import Foundation
import InboxCore
import Darwin
import os

enum Live {
    private static let orcaBundleID = "com.stablyai.orca"

    static func resolveAppURL() -> URL? {
        let fm = FileManager.default
        let candidates: [URL] = [
            URL(fileURLWithPath: "/Applications/Orca.app", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appending(path: "Applications/Orca.app", directoryHint: .isDirectory),
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: orcaBundleID)
        ].compactMap { $0 }

        for candidate in candidates {
            let cliPath = candidate.appending(path: "Contents/Resources/bin/orca").path
            if fm.isExecutableFile(atPath: cliPath) {
                return candidate
            }
        }
        return nil
    }

    private static func runCLI(_ arguments: [String], timeoutSeconds: TimeInterval = 7) throws -> Data {
        guard let appURL = resolveAppURL() else { throw InboxFailure.missingCLI }
        let cliPath = appURL.appending(path: "Contents/Resources/bin/orca").path
        guard FileManager.default.isExecutableFile(atPath: cliPath) else { throw InboxFailure.missingCLI }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": NSTemporaryDirectory()
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        let expired = OSAllocatedUnfairLock(initialState: false)
        let timeout = DispatchWorkItem {
            if process.isRunning {
                expired.withLock { $0 = true }
                _ = kill(process.processIdentifier, SIGKILL)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        _ = completion.wait(timeout: .now() + 1)
        if expired.withLock({ $0 }) { throw InboxFailure.timeout }
        return data
    }

    static func fetchHosts() throws -> [HostTarget] {
        let data = try runCLI(["host", "list", "--json"], timeoutSeconds: 5)
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["ok"] as? Bool == true,
              let result = envelope["result"] as? [String: Any],
              result["hosts"] is [[String: Any]] else { throw InboxFailure.unreadable }
        return decodeHosts(data)
    }

    static func fetch(environment: String = "local") throws -> Snapshot {
        let data = try runCLI(["agent", "list", "--environment", environment, "--json"])
        return try decodeSnapshot(data)
    }
}
