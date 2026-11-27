import AppKit
import Foundation
import InboxCore
import Darwin
import os

enum Live {
    static let appURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Applications/Orca.app", directoryHint: .isDirectory)

    static func fetch() throws -> Snapshot {
        let cliPath = appURL.appending(path: "Contents/Resources/bin/orca").path
        guard FileManager.default.isExecutableFile(atPath: cliPath) else { throw InboxFailure.missingCLI }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["agent", "list", "--environment", "local", "--json"]
        process.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "TMPDIR": NSTemporaryDirectory()]
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
        DispatchQueue.global().asyncAfter(deadline: .now() + 7, execute: timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        _ = completion.wait(timeout: .now() + 1)
        if expired.withLock({ $0 }) { throw InboxFailure.timeout }
        return try decodeSnapshot(data)
    }
}
