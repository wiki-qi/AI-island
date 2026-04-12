#!/usr/bin/env swift

/// 模拟脚本：向 NotchAgent 发送模拟事件，测试 UI 效果
/// 用法: swift Scripts/simulate.swift

import Foundation

let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let socketPath = supportDir.appendingPathComponent("NotchAgent/notch.sock").path

func sendMessage(_ json: [String: Any]) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        print("❌ 无法创建 socket，请确保 NotchAgent 已启动")
        return
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { ptr in
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            let raw = UnsafeMutableRawPointer(sunPath)
            raw.copyMemory(from: ptr, byteCount: min(socketPath.utf8.count, 104))
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        print("❌ 无法连接到 NotchAgent (socket: \(socketPath))")
        print("   请先启动 NotchAgent: swift run NotchAgent")
        return
    }

    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
    var payload = data
    payload.append(0x0A)
    payload.withUnsafeBytes { ptr in
        _ = write(fd, ptr.baseAddress!, ptr.count)
    }
    print("✅ 已发送: \(json["type"] ?? "unknown")")
}

let sessionId = UUID().uuidString

print("🏝️  NotchAgent 模拟测试")
print("========================")
print("Socket: \(socketPath)")
print("Session: \(sessionId)")
print("")

// 1. 模拟 Claude Code 会话开始
print("📍 Step 1: 启动 Claude Code 会话...")
sendMessage([
    "type": "sessionStart",
    "sessionId": sessionId,
    "payload": [
        "agent": "Claude Code",
        "name": "fix auth bug",
        "terminal": "iTerm2"
    ]
])
Thread.sleep(forTimeInterval: 2)

// 2. 模拟 Agent 思考
print("📍 Step 2: Agent 正在思考...")
sendMessage([
    "type": "agentMessage",
    "sessionId": sessionId,
    "payload": [
        "messageType": "agentThinking",
        "content": "Let me look at the auth module and find the bug."
    ]
])
Thread.sleep(forTimeInterval: 2)

// 3. 模拟工具使用（读文件）
print("📍 Step 3: Agent 读取文件...")
sendMessage([
    "type": "toolUse",
    "sessionId": sessionId,
    "payload": [
        "tool": "Read",
        "description": "src/auth/middleware.ts (1.2 KB)"
    ]
])
Thread.sleep(forTimeInterval: 2)

// 4. 模拟权限请求（写文件）
print("📍 Step 4: Agent 请求写入权限...")
sendMessage([
    "type": "approvalRequest",
    "sessionId": sessionId,
    "payload": [
        "tool": "Edit",
        "description": "修改 src/auth/middleware.ts — 修复 token 验证跳过过期检查的问题",
        "filePath": "src/auth/middleware.ts"
    ]
])
Thread.sleep(forTimeInterval: 5)

// 5. 模拟第二个 Agent（Codex）
let session2 = UUID().uuidString
print("📍 Step 5: 启动 Codex 会话...")
sendMessage([
    "type": "sessionStart",
    "sessionId": session2,
    "payload": [
        "agent": "Codex",
        "name": "backend server",
        "terminal": "Terminal"
    ]
])
Thread.sleep(forTimeInterval: 2)

// 6. 模拟第三个 Agent（Gemini CLI）
let session3 = UUID().uuidString
print("📍 Step 6: 启动 Gemini CLI 会话...")
sendMessage([
    "type": "sessionStart",
    "sessionId": session3,
    "payload": [
        "agent": "Gemini CLI",
        "name": "optimize queries",
        "terminal": "Ghostty"
    ]
])
Thread.sleep(forTimeInterval: 2)

print("")
print("🎉 模拟完成！")
print("   你应该能在 MacBook 刘海位置看到 3 个 Agent 的状态")
print("   其中 Claude Code 有一个待审批的写入请求")
print("   鼠标移到刘海区域可以展开面板查看详情")
