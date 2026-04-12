import Foundation

/// NotchAgent Bridge — invoked by AI tool hooks
/// Usage: notch-agent-bridge --source <claude|gemini|codex> [--event <name>]

// MARK: - Parse args

var source = "unknown"
var eventArg = ""
let args = Array(CommandLine.arguments.dropFirst())
var idx = 0
while idx < args.count {
    if args[idx] == "--source", idx + 1 < args.count {
        idx += 1; source = args[idx]
    } else if args[idx] == "--event", idx + 1 < args.count {
        idx += 1; eventArg = args[idx]
    }
    idx += 1
}

// MARK: - Read stdin

let stdinData = FileHandle.standardInput.readDataToEndOfFile()

// MARK: - Parse payload

var payload: [String: Any] = ["source": source]
if !stdinData.isEmpty,
   let json = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] {
    payload.merge(json) { old, _ in old }
}

// MARK: - Determine event type

let hookEvent = eventArg.isEmpty
    ? ((payload["hook_event_name"] as? String)
       ?? (payload["hook_event"] as? String)
       ?? (payload["event"] as? String)
       ?? (payload["type"] as? String)
       ?? "")
    : eventArg

let lower = hookEvent.lowercased()
let messageType: String
if lower.contains("sessionstart") || lower.contains("session_start") {
    messageType = "sessionStart"
} else if lower.contains("sessionend") || lower.contains("session_end") {
    messageType = "sessionEnd"
} else if lower == "stop" {
    messageType = "sessionCompleted"
} else if lower.contains("permission") || lower.contains("approval") {
    messageType = "approvalRequest"
} else if lower.contains("tool") {
    messageType = "toolUse"
} else if lower.contains("prompt") {
    messageType = "agentMessage"
} else if lower.contains("error") {
    messageType = "agentMessage"
} else {
    messageType = "agentMessage"
}

// MARK: - Session ID

let sessionId = (payload["session_id"] as? String)
    ?? (payload["conversation_id"] as? String)
    ?? ProcessInfo.processInfo.environment["CLAUDE_SESSION_ID"]
    ?? ProcessInfo.processInfo.environment["CODEX_SESSION_ID"]
    ?? "\(source)-default"

let message: [String: Any] = [
    "type": messageType,
    "sessionId": sessionId,
    "payload": payload
]

// MARK: - Send to NotchAgent

let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let socketPath = supportDir.appendingPathComponent("NotchAgent/notch.sock").path

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else {
    print("{\"continue\":true}")
    exit(0)
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
socketPath.withCString { ptr in
    withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
        UnsafeMutableRawPointer(sunPath).copyMemory(from: ptr, byteCount: min(socketPath.utf8.count, 104))
    }
}

let connected = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

if connected == 0 {
    if let data = try? JSONSerialization.data(withJSONObject: message) {
        var sendData = data
        sendData.append(0x0A)
        sendData.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
    }
}

close(fd)
print("{\"continue\":true}")
