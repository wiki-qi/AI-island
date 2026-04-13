import Foundation

// MARK: - Session Phase (matches Open Vibe Island)

enum SessionPhase: String, Codable, Equatable {
    case running
    case waitingForApproval
    case waitingForAnswer
    case completed

    var requiresAttention: Bool {
        self == .waitingForApproval || self == .waitingForAnswer
    }
}

// MARK: - Agent Session

struct AgentSession: Identifiable, Codable {
    let id: UUID
    var agentType: AgentType
    var name: String
    var terminal: TerminalInfo
    var phase: SessionPhase
    var summary: String
    var startTime: Date
    var updatedAt: Date
    var messages: [AgentMessage]
    var pendingApproval: ApprovalRequest?

    /// Whether lifecycle is driven by hook events (SessionStart/SessionEnd)
    var isHookManaged: Bool
    /// Whether SessionEnd hook was received
    var isSessionEnded: Bool
    /// Number of consecutive cleanup polls with no activity
    var inactivePolls: Int

    init(agentType: AgentType, name: String, terminal: TerminalInfo) {
        self.id = UUID()
        self.agentType = agentType
        self.name = name
        self.terminal = terminal
        self.phase = .running
        self.summary = ""
        self.startTime = Date()
        self.updatedAt = Date()
        self.messages = []
        self.pendingApproval = nil
        self.isHookManaged = true
        self.isSessionEnded = false
        self.inactivePolls = 0
    }

    /// Visibility rule — matches Open Vibe Island logic
    var isVisibleInIsland: Bool {
        // Always show sessions that need user action
        if phase.requiresAttention { return true }
        // Running sessions are always visible
        if phase == .running { return true }
        // Completed sessions: show briefly (handled by reconciler), hide if ended
        if phase == .completed {
            // Show for 5 minutes after completion
            let timeSinceUpdate = Date().timeIntervalSince(updatedAt)
            if timeSinceUpdate < 300 { return true }
            return false
        }
        return false
    }

    var elapsed: String {
        let interval = Date().timeIntervalSince(startTime)
        let minutes = Int(interval) / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    // Keep backward compat for views that use .status
    var status: SessionStatus {
        switch phase {
        case .running: return .running
        case .waitingForApproval, .waitingForAnswer: return .waiting
        case .completed: return .completed
        }
    }
}

enum AgentType: String, Codable, CaseIterable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case geminiCLI = "Gemini CLI"
    case cursor = "Cursor"
    case openCode = "OpenCode"
    case droid = "Droid"
    case kiro = "Kiro"
    case copilot = "Copilot"

    var icon: String {
        switch self {
        case .claudeCode: return "c.circle.fill"
        case .codex: return "x.circle.fill"
        case .geminiCLI: return "g.circle.fill"
        case .cursor: return "cursorarrow"
        case .openCode: return "chevron.left.forwardslash.chevron.right"
        case .droid: return "cpu"
        case .kiro: return "k.circle.fill"
        case .copilot: return "airplane"
        }
    }
}

enum SessionStatus: String, Codable {
    case running
    case waiting
    case completed
    case error
}

struct TerminalInfo: Codable {
    var app: TerminalApp
    var windowId: Int?
    var tabIndex: Int?
    var paneId: String?
    var tty: String?
    var workingDirectory: String?
    var paneTitle: String?
}

enum TerminalApp: String, Codable {
    case iterm2 = "iTerm2"
    case ghostty = "Ghostty"
    case terminal = "Terminal"
    case warp = "Warp"
    case alacritty = "Alacritty"
    case kitty = "Kitty"
    case vscode = "VS Code"
    case cursor = "Cursor"
}
