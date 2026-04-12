import Foundation

/// Messages exchanged over the Unix socket between bridge and app
struct SocketMessage: Codable {
    let type: SocketMessageType
    let sessionId: String?
    let payload: [String: AnyCodable]

    init(type: SocketMessageType, sessionId: String? = nil, payload: [String: AnyCodable] = [:]) {
        self.type = type
        self.sessionId = sessionId
        self.payload = payload
    }
}

enum SocketMessageType: String, Codable {
    // From bridge to app
    case sessionStart
    case sessionEnd
    case sessionCompleted  // Stop/turn complete — session stays visible
    case agentMessage
    case toolUse
    case approvalRequest
    case askUser

    // From app to bridge
    case approvalResponse
    case askUserResponse
}

/// Type-erased Codable wrapper
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let arr as [AnyCodable]: try container.encode(arr)
        default: try container.encode("")
        }
    }
}
