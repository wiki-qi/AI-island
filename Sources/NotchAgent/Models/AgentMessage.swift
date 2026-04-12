import Foundation

/// A message or event from an agent session
struct AgentMessage: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: MessageType
    let content: String

    init(type: MessageType, content: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.content = content
    }
}

enum MessageType: String, Codable {
    case userPrompt
    case agentThinking
    case toolUse       // Read, Write, Bash, etc.
    case toolResult
    case completion
    case error
}

/// A pending approval request from an agent
struct ApprovalRequest: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let toolName: String
    let description: String
    let filePath: String?
    let diff: DiffContent?
    let timestamp: Date

    init(sessionId: UUID, toolName: String, description: String, filePath: String? = nil, diff: DiffContent? = nil) {
        self.id = UUID()
        self.sessionId = sessionId
        self.toolName = toolName
        self.description = description
        self.filePath = filePath
        self.diff = diff
        self.timestamp = Date()
    }
}

struct DiffContent: Codable {
    let oldLines: [String]
    let newLines: [String]
    let additions: Int
    let deletions: Int
}
