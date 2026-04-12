import Foundation

/// Auto-configures hooks for supported AI coding tools — matches Vibe Island format exactly
struct HookConfigurator {
    static let bridgeDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notch-agent/bin").path
    }()

    static let bridgePath: String = {
        return "\(bridgeDir)/notch-agent-bridge"
    }()

    static let socketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("NotchAgent/notch.sock").path
    }()

    /// Configure all supported tools
    static func configureAll() {
        installBridge()
        configureGeminiCLI()
        configureClaudeCode()
        configureCodex()
        configureKiroCLI()
    }

    /// Backup a file before modifying it (only on first-ever injection)
    private static func backupIfNeeded(_ file: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return }

        let backupDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch-agent/backups")
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let fileName = file.lastPathComponent
        let parentName = file.deletingLastPathComponent().lastPathComponent
        let backupPrefix = "\(parentName)_\(fileName)"

        // Check if we already have a backup for this file
        let existing = (try? fm.contentsOfDirectory(atPath: backupDir.path)) ?? []
        if existing.contains(where: { $0.hasPrefix(backupPrefix) }) {
            return // Already backed up before
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = "\(backupPrefix).\(timestamp).bak"
        let backupURL = backupDir.appendingPathComponent(backupName)

        try? fm.copyItem(at: file, to: backupURL)
        print("[HookConfig] Backed up \(file.lastPathComponent) → \(backupName)")
    }

    /// Copy bridge binary to ~/.notch-agent/bin/
    private static func installBridge() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: bridgeDir, withIntermediateDirectories: true)

        // If running from Xcode, the bridge is in the build products
        if let bundleBridge = Bundle.main.url(forAuxiliaryExecutable: "NotchBridge") {
            try? fm.copyItem(at: bundleBridge, to: URL(fileURLWithPath: bridgePath))
        }

        // Make executable
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgePath)
        print("[HookConfig] Bridge installed at \(bridgePath)")
    }

    // MARK: - Gemini CLI (settings.json)
    // Format: hooks.BeforeTool/AfterTool/BeforeAgent/AfterAgent

    static func configureGeminiCLI() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
        let settingsFile = configDir.appendingPathComponent("settings.json")

        guard FileManager.default.fileExists(atPath: configDir.path) else {
            print("[HookConfig] Gemini CLI not installed, skipping")
            return
        }

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        backupIfNeeded(settingsFile)

        let command = "\(bridgePath) --source gemini"
        let hookEntry: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": 5000
            ] as [String: Any]]
        ]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Remove old notch-agent and vibe-island hooks, add ours
        let events = ["BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "SessionStart", "SessionEnd"]
        for event in events {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks.removeAll { entry in
                if let innerHooks = entry["hooks"] as? [[String: Any]] {
                    return innerHooks.contains {
                        let cmd = $0["command"] as? String ?? ""
                        return cmd.contains("notch-agent") || cmd.contains("vibe-island") || cmd.contains("notch-bridge")
                    }
                }
                return false
            }
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }

        // Remove old-style tool_use key if present
        hooks.removeValue(forKey: "tool_use")

        settings["hooks"] = hooks

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settingsFile)
        }
        print("[HookConfig] Gemini CLI configured")
    }

    // MARK: - Claude Code (settings.json)
    // Format: hooks.PreToolUse/PostToolUse as arrays of hook objects

    static func configureClaudeCode() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let settingsFile = configDir.appendingPathComponent("settings.json")

        guard FileManager.default.fileExists(atPath: configDir.path) else {
            print("[HookConfig] Claude Code not installed, skipping")
            return
        }

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        backupIfNeeded(settingsFile)

        let command = "\(bridgePath) --source claude"

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Events with matcher: "*"
        let matcherEvents = ["Notification", "PreToolUse", "PostToolUse", "PermissionRequest"]
        // Events without matcher
        let plainEvents = ["SessionStart", "SessionEnd", "Stop", "SubagentStart", "SubagentStop", "UserPromptSubmit", "PreCompact"]

        func cleanAndBuild(_ eventHooks: [[String: Any]]) -> [[String: Any]] {
            let cleaned = eventHooks.filter { entry in
                // Remove old flat-style notch-agent hooks
                if let cmd = entry["command"] as? String, cmd.contains("notch-agent") { return false }
                // Remove old vibe-island hooks
                if let innerHooks = entry["hooks"] as? [[String: Any]] {
                    let hasOld = innerHooks.contains {
                        let cmd = $0["command"] as? String ?? ""
                        return cmd.contains("notch-agent") || cmd.contains("vibe-island") || cmd.contains("notch-bridge")
                    }
                    if hasOld { return false }
                }
                return true
            }
            return cleaned
        }

        for event in matcherEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks = cleanAndBuild(eventHooks)

            var entry: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": command,
                ] as [String: Any]],
                "matcher": "*"
            ]
            // PermissionRequest needs long timeout for blocking approval
            if event == "PermissionRequest" {
                entry["hooks"] = [[
                    "type": "command",
                    "command": command,
                    "timeout": 86400
                ] as [String: Any]]
            }
            eventHooks.append(entry)
            hooks[event] = eventHooks
        }

        for event in plainEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks = cleanAndBuild(eventHooks)
            eventHooks.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                ] as [String: Any]]
            ] as [String: Any])
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks

        // Remove Vibe Island statusLine if present
        if let statusLine = settings["statusLine"] as? [String: Any],
           let cmd = statusLine["command"] as? String,
           cmd.contains("vibe-island") {
            settings.removeValue(forKey: "statusLine")
        }

        // Also set env to disable terminal title (like Vibe Island does)
        var env = settings["env"] as? [String: String] ?? [:]
        env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"
        settings["env"] = env

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settingsFile)
        }
        print("[HookConfig] Claude Code configured")
    }

    // MARK: - Codex (~/.codex/config.toml notify + hooks.json)

    static func configureCodex() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")

        guard FileManager.default.fileExists(atPath: configDir.path) else {
            print("[HookConfig] Codex not installed, skipping")
            return
        }

        // 1. Add notify to config.toml
        let configFile = configDir.appendingPathComponent("config.toml")
        backupIfNeeded(configFile)
        var toml = (try? String(contentsOf: configFile, encoding: .utf8)) ?? ""

        let notifyLine = "notify = [\"\(bridgePath)\", \"--source\", \"codex\"]"

        // Remove old notify lines
        let lines = toml.components(separatedBy: "\n").filter {
            !$0.contains("notch-agent") || !$0.contains("notify")
        }
        toml = lines.joined(separator: "\n")

        // Add notify if not present
        if !toml.contains("notify") || toml.contains("notch-agent") {
            // Remove any existing notify line
            let filtered = toml.components(separatedBy: "\n").filter { !$0.hasPrefix("notify") }
            toml = filtered.joined(separator: "\n")
            // Add after model line or at top
            if let modelRange = toml.range(of: "\n", options: [], range: toml.startIndex..<toml.endIndex) {
                toml.insert(contentsOf: "\n\(notifyLine)", at: modelRange.lowerBound)
            } else {
                toml = notifyLine + "\n" + toml
            }
        }

        // Ensure codex_hooks feature is enabled
        if !toml.contains("codex_hooks") {
            if let featuresRange = toml.range(of: "[features]") {
                let insertPos = toml.index(after: toml[featuresRange.upperBound...].firstIndex(of: "\n") ?? featuresRange.upperBound)
                toml.insert(contentsOf: "codex_hooks = true\n", at: insertPos)
            }
        }

        try? toml.write(to: configFile, atomically: true, encoding: .utf8)

        // 2. Write hooks.json — Codex format: { hooks: { EventName: [{ hooks: [...] }] } }
        let hooksFile = configDir.appendingPathComponent("hooks.json")
        backupIfNeeded(hooksFile)
        let command = "\(bridgePath) --source codex"

        var rootObject: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rootObject = json
        }

        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]

        // Clean old hooks from all events
        for (eventName, value) in hooksObject {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll { group in
                guard let innerHooks = group["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains {
                    let cmd = $0["command"] as? String ?? ""
                    return cmd.contains("notch-agent") || cmd.contains("vibe-island") || cmd.contains("notch-bridge")
                }
            }
            if groups.isEmpty {
                hooksObject.removeValue(forKey: eventName)
            } else {
                hooksObject[eventName] = groups
            }
        }

        // Add our hooks
        let events: [(name: String, matcher: String?)] = [
            ("SessionStart", "startup|resume"),
            ("UserPromptSubmit", nil),
            ("PostToolUse", nil),
            ("Stop", nil),
        ]

        for spec in events {
            var groups = hooksObject[spec.name] as? [[String: Any]] ?? []
            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 45
                ] as [String: Any]]
            ]
            if let matcher = spec.matcher {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooksObject[spec.name] = groups
        }

        rootObject["hooks"] = hooksObject

        if let data = try? JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: hooksFile)
        }

        print("[HookConfig] Codex configured (notify + hooks.json)")
    }

    // MARK: - Kiro CLI (~/.kiro/agents/default.json)

    static func configureKiroCLI() {
        let agentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kiro/agents")

        guard FileManager.default.fileExists(atPath: agentDir.deletingLastPathComponent().path) else {
            print("[HookConfig] Kiro CLI not installed, skipping")
            return
        }

        try? FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        let agentFile = agentDir.appendingPathComponent("default.json")
        backupIfNeeded(agentFile)
        let command = bridgePath

        // If file exists, merge hooks into it; otherwise create new
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: agentFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }

        // Set defaults if new file
        if config["name"] == nil { config["name"] = "default" }
        if config["tools"] == nil { config["tools"] = ["*"] }
        if config["includeMcpJson"] == nil { config["includeMcpJson"] = true }

        // Set hooks
        let hookCommand = "\(command) --source kiro"
        config["hooks"] = [
            "agentSpawn": [["command": hookCommand]],
            "userPromptSubmit": [["command": hookCommand]],
            "postToolUse": [["matcher": "*", "command": hookCommand]],
            "stop": [["command": hookCommand]]
        ] as [String: Any]

        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: agentFile)
        }
        print("[HookConfig] Kiro CLI configured")
    }
}
