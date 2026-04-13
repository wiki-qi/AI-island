import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var sessions: [AgentSession] = []
    @Published var notchStatus: NotchStatus = .closed

    enum NotchStatus: Equatable {
        case closed
        case opened
    }

    /// Map external session IDs (from hooks) to internal UUIDs
    private var externalToInternal: [String: UUID] = [:]
    private var cleanupTimer: Timer?

    // MARK: - Computed

    /// Sessions visible in the island UI
    var activeSessions: [AgentSession] {
        sessions
            .filter(\.isVisibleInIsland)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var liveSessionCount: Int { activeSessions.count }

    var pendingApprovals: [ApprovalRequest] {
        sessions.compactMap(\.pendingApproval)
    }

    // MARK: - Notch control

    func notchOpen() { notchStatus = .opened }
    func notchClose() { notchStatus = .closed }

    // MARK: - Cleanup timer

    func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcileSessions() }
        }
    }

    /// Periodic reconciliation — increment inactive polls, remove invisible sessions
    private func reconcileSessions() {
        let now = Date()

        // Remove sessions that are no longer visible and older than 5 minutes
        sessions.removeAll { session in
            !session.isVisibleInIsland &&
            now.timeIntervalSince(session.updatedAt) > 300
        }

        // Clean up stale external ID mappings
        let activeIDs = Set(sessions.map(\.id))
        let staleKeys = externalToInternal.filter { !activeIDs.contains($0.value) }.map(\.key)
        for key in staleKeys {
            externalToInternal.removeValue(forKey: key)
        }
    }

    func clearAll() {
        sessions.removeAll()
        externalToInternal.removeAll()
    }

    // MARK: - Socket Message Handling

    func handleSocketMessage(_ message: SocketMessage) {
        let source = extractString("source", from: message.payload) ?? ""
        let externalId = message.sessionId ?? ""

        print("[Session] \(message.type.rawValue) | source=\(source) | sid=\(externalId)")

        let sessionIdx = findOrCreateSession(externalId: externalId, source: source, payload: message.payload)

        guard let idx = sessionIdx else { return }

        // Touch activity
        sessions[idx].updatedAt = Date()
        sessions[idx].inactivePolls = 0

        // Update terminal info if payload has newer cwd
        if let cwd = extractString("cwd", from: message.payload), !cwd.isEmpty {
            sessions[idx].terminal.workingDirectory = cwd
        }

        // If session was completed but new activity arrives, revive it
        if sessions[idx].phase == .completed {
            sessions[idx].phase = .running
            sessions[idx].isSessionEnded = false
        }

        switch message.type {
        case .sessionStart:
            sessions[idx].phase = .running
            sessions[idx].isSessionEnded = false
            SoundManager.shared.play(.sessionStart)

        case .sessionEnd:
            // True session end — agent process exited
            sessions[idx].phase = .completed
            sessions[idx].isSessionEnded = true
            let summary = extractString("summary", from: message.payload)
                ?? extractString("last_assistant_message", from: message.payload)
                ?? "Session ended."
            sessions[idx].summary = summary
            SoundManager.shared.play(.sessionComplete)

        case .sessionCompleted:
            // Turn completed (Stop) — session stays visible, can resume
            sessions[idx].phase = .completed
            // Do NOT set isSessionEnded — session remains visible
            let summary = extractString("summary", from: message.payload)
                ?? extractString("last_assistant_message", from: message.payload)
                ?? "Turn completed."
            sessions[idx].summary = summary
            SoundManager.shared.play(.sessionComplete)

        case .agentMessage:
            let content = extractString("content", from: message.payload)
                ?? extractString("message", from: message.payload)
                ?? extractString("raw", from: message.payload)
                ?? ""
            if !content.isEmpty {
                sessions[idx].messages.append(AgentMessage(type: .agentThinking, content: content))
                sessions[idx].summary = String(content.prefix(100))
            }

        case .toolUse:
            let tool = extractString("tool_name", from: message.payload)
                ?? extractString("tool", from: message.payload)
                ?? "tool"
            let input = extractString("tool_input", from: message.payload)
                ?? extractString("description", from: message.payload)
                ?? ""
            let display = input.isEmpty ? tool : "\(tool): \(String(input.prefix(80)))"
            sessions[idx].messages.append(AgentMessage(type: .toolUse, content: display))
            sessions[idx].summary = display

        case .approvalRequest:
            let tool = extractString("tool_name", from: message.payload)
                ?? extractString("tool", from: message.payload)
                ?? "permission"
            let desc = extractString("description", from: message.payload)
                ?? extractString("message", from: message.payload)
                ?? ""
            let filePath = extractString("file_path", from: message.payload)
                ?? extractString("filePath", from: message.payload)
            let request = ApprovalRequest(
                sessionId: sessions[idx].id,
                toolName: tool, description: desc, filePath: filePath
            )
            sessions[idx].pendingApproval = request
            sessions[idx].phase = .waitingForApproval
            sessions[idx].summary = desc
            SoundManager.shared.play(.approvalNeeded)

        case .askUser:
            let question = extractString("question", from: message.payload)
                ?? extractString("message", from: message.payload)
                ?? ""
            let request = ApprovalRequest(
                sessionId: sessions[idx].id,
                toolName: "AskUser", description: question
            )
            sessions[idx].pendingApproval = request
            sessions[idx].phase = .waitingForAnswer
            sessions[idx].summary = question
            SoundManager.shared.play(.approvalNeeded)

        default:
            break
        }
    }

    // MARK: - Find or create session

    private func findOrCreateSession(externalId: String, source: String, payload: [String: AnyCodable]) -> Int? {
        // Look up existing session by external ID
        if !externalId.isEmpty, let internalId = externalToInternal[externalId] {
            if let idx = sessions.firstIndex(where: { $0.id == internalId }) {
                return idx
            }
            // Mapping is stale — remove it and create new
            externalToInternal.removeValue(forKey: externalId)
        }

        // Create new session
        let agentType: AgentType
        switch source.lowercased() {
        case "claude": agentType = .claudeCode
        case "gemini": agentType = .geminiCLI
        case "codex": agentType = .codex
        case "cursor": agentType = .cursor
        case "kiro": agentType = .kiro
        default: agentType = .claudeCode
        }

        let name = extractString("session_name", from: payload)
            ?? extractString("prompt", from: payload)
            ?? "\(agentType.rawValue)"

        let termName = extractString("terminal_app", from: payload)
            ?? extractString("terminal", from: payload) ?? ""
        let termApp: TerminalApp
        if let parsed = TerminalApp(rawValue: termName) {
            termApp = parsed
        } else {
            // Auto-detect from frontmost app
            termApp = Self.detectFrontmostTerminal()
        }

        // Extract terminal jump info from payload
        let cwd = extractString("cwd", from: payload)
        let paneId = extractString("terminal_session_id", from: payload)
            ?? extractString("pane_id", from: payload)
        let tty = extractString("tty", from: payload)
        let paneTitle = extractString("pane_title", from: payload)
            ?? extractString("session_name", from: payload)
            ?? source  // fallback to agent source name (claude/codex/gemini/kiro)

        var termInfo = TerminalInfo(app: termApp)
        termInfo.workingDirectory = cwd
        termInfo.paneId = paneId
        termInfo.tty = tty
        termInfo.paneTitle = paneTitle

        let session = AgentSession(
            agentType: agentType,
            name: String(name.prefix(40)),
            terminal: termInfo
        )

        sessions.append(session)
        if !externalId.isEmpty {
            externalToInternal[externalId] = session.id
        }

        print("[Session] Created: \(agentType.rawValue) — \(session.name)")
        return sessions.count - 1
    }

    // MARK: - Approval Actions

    func approve(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].pendingApproval = nil
        sessions[idx].phase = .running
        sessions[idx].summary = "Permission approved."
        sessions[idx].updatedAt = Date()
        SoundManager.shared.play(.approved)
    }

    func deny(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].pendingApproval = nil
        sessions[idx].phase = .completed
        sessions[idx].summary = "Permission denied."
        sessions[idx].updatedAt = Date()
        SoundManager.shared.play(.denied)
    }

    // MARK: - Helpers

    private static let bundleToTerminal: [String: TerminalApp] = [
        "com.mitchellh.ghostty": .ghostty,
        "com.googlecode.iterm2": .iterm2,
        "com.apple.Terminal": .terminal,
        "dev.warp.Warp-Stable": .warp,
        "com.microsoft.VSCode": .vscode,
        "com.todesktop.230313mzl4w4u92": .cursor,
        "io.alacritty": .alacritty,
        "net.kovidgoyal.kitty": .kitty,
    ]

    private static func detectFrontmostTerminal() -> TerminalApp {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else { return .terminal }
        return bundleToTerminal[bundleId] ?? .terminal
    }

    private func extractString(_ key: String, from payload: [String: AnyCodable]) -> String? {
        guard let val = payload[key] else { return nil }
        if let str = val.value as? String { return str }
        return nil
    }
}
