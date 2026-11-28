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

    private static func assertEnvelopeOK(_ data: Data) throws {
        struct Problem: Decodable { let code: String?; let message: String? }
        struct Envelope: Decodable { let ok: Bool; let error: Problem? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw InboxFailure.unreadable
        }
        if !envelope.ok {
            if let message = envelope.error?.message, !message.isEmpty {
                throw ActionError(message: message)
            }
            throw InboxFailure.rejected(envelope.error?.code ?? "")
        }
    }

    struct ActionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
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

    static func fetchInstalledAgents(environment: String = "local") throws -> [InstalledAgentOption] {
        let data = try runCLI(["agent", "installed", "--environment", environment, "--json"], timeoutSeconds: 5)
        return decodeInstalledAgents(data)
    }

    static func fetchTranscript(sessionId: String, environment: String = "local", limit: Int = 8) throws -> AgentTranscriptPage {
        let data = try runCLI([
            "agent", "read", "orca_session_id:\(sessionId)",
            "--limit", "\(limit)",
            "--environment", environment,
            "--json"
        ], timeoutSeconds: 8)
        return try decodeTranscriptPage(data)
    }

    static func fetchPendingPrompts(sessionId: String, environment: String = "local") -> [AgentPendingPrompt] {
        guard let data = try? runCLI([
            "agent", "requests", "orca_session_id:\(sessionId)",
            "--environment", environment,
            "--json"
        ], timeoutSeconds: 5) else {
            return []
        }
        return decodePendingPrompts(data)
    }

    static func dispatchAgent(
        worktreeId: String,
        agent: String,
        prompt: String,
        environment: String = "local"
    ) throws {
        let selector = worktreeId.hasPrefix("folder:") ? worktreeId : "id:\(worktreeId)"
        let data = try runCLI([
            "agent", "launch",
            "--agent", agent,
            "--worktree", selector,
            "--prompt", prompt,
            "--environment", environment,
            "--json"
        ], timeoutSeconds: 15)
        try assertEnvelopeOK(data)
    }

    static func replyToAgent(
        sessionId: String,
        text: String,
        environment: String = "local"
    ) throws {
        let data = try runCLI([
            "agent", "reply", "orca_session_id:\(sessionId)",
            "--text", text,
            "--environment", environment,
            "--json"
        ], timeoutSeconds: 12)
        try assertEnvelopeOK(data)
    }

    static func respondToPrompt(
        sessionId: String,
        prompt: AgentPendingPrompt,
        option: AgentPromptOption,
        environment: String = "local"
    ) throws {
        var args = [
            "agent", "respond", "orca_session_id:\(sessionId)",
            "--item", prompt.itemId,
            "--revision", "\(prompt.revision)",
            "--kind", prompt.kind,
            "--option", option.id,
            "--environment", environment,
            "--json"
        ]
        if let questionId = prompt.questionId, !questionId.isEmpty {
            args.append(contentsOf: ["--question-id", questionId])
        }
        let data = try runCLI(args, timeoutSeconds: 12)
        try assertEnvelopeOK(data)
    }
}
