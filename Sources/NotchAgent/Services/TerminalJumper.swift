import Foundation
import AppKit

/// Handles jumping to the correct terminal window/tab/pane
struct TerminalJumper {

    static func jump(to terminal: TerminalInfo) {
        // Run on background thread — osascript is a subprocess, safe off main
        DispatchQueue.global(qos: .userInitiated).async {
            performJump(to: terminal)
        }
    }

    private static func performJump(to terminal: TerminalInfo) {
        switch terminal.app {
        case .iterm2:
            jumpToITerm2(terminal)
        case .ghostty:
            jumpToGhostty(terminal)
        case .vscode:
            jumpToVSCodeFamily(bundleId: "com.microsoft.VSCode", cli: "code", terminal: terminal)
        case .cursor:
            jumpToVSCodeFamily(bundleId: "com.todesktop.230313mzl4w4u92", cli: "cursor", terminal: terminal)
        case .warp:
            activateApp(bundleId: "dev.warp.Warp-Stable")
        default:
            // Unknown or .terminal — try all running terminals in order
            if tryGhosttyJump(terminal) { return }
            if tryITermJump(terminal) { return }
            jumpToTerminalApp(terminal)
        }
    }

    /// Try jumping to Ghostty even when terminal type is unknown — returns true if matched
    private static func tryGhosttyJump(_ terminal: TerminalInfo) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").first != nil else {
            return false
        }
        return runAppleScript(ghosttyScript(terminal)) == "matched"
    }

    /// Try jumping to iTerm2 when terminal type is unknown — returns true if matched
    private static func tryITermJump(_ terminal: TerminalInfo) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil else {
            return false
        }
        // Use cwd last part to match iTerm session name
        let cwdLastPart = escapeAS(terminal.workingDirectory.flatMap { URL(fileURLWithPath: $0).lastPathComponent })
        guard !cwdLastPart.isEmpty else { return false }

        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if (name of aSession as text) contains "\(cwdLastPart)" then
                            select aWindow
                            tell aWindow to select aTab
                            select aSession
                            return "matched"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """
        return runAppleScript(script) == "matched"
    }

    // MARK: - iTerm2 (AppleScript — session ID or TTY matching)

    private static func jumpToITerm2(_ terminal: TerminalInfo) {
        let sessionId = escapeAS(terminal.paneId)
        let tty = escapeAS(terminal.tty)

        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set matched to false
                        if "\(sessionId)" is not "" and (id of aSession as text) is "\(sessionId)" then
                            set matched to true
                        end if
                        if not matched and "\(tty)" is not "" and (tty of aSession as text) is "\(tty)" then
                            set matched to true
                        end if
                        if matched then
                            select aWindow
                            tell aWindow to select aTab
                            select aSession
                            return "matched"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """

        let result = runAppleScript(script)
        if result != "matched" {
            // Fallback: just activate with window/tab index
            if let windowId = terminal.windowId, let tabIndex = terminal.tabIndex {
                runAppleScript("""
                tell application "iTerm"
                    activate
                    tell window id \(windowId)
                        select tab \(tabIndex)
                    end tell
                end tell
                """)
            } else {
                activateApp(bundleId: "com.googlecode.iterm2")
            }
        }
    }

    // MARK: - Ghostty (AppleScript — ID, working directory, or title matching)

    private static func jumpToGhostty(_ terminal: TerminalInfo) {
        let result = runAppleScript(ghosttyScript(terminal))
        if result != "matched" {
            activateApp(bundleId: "com.mitchellh.ghostty")
        }
    }

    private static func ghosttyScript(_ terminal: TerminalInfo) -> String {
        let terminalId = escapeAS(terminal.paneId)
        let workDir = escapeAS(terminal.workingDirectory)
        let title = escapeAS(terminal.paneTitle)
        let cwdLastPart = escapeAS(terminal.workingDirectory.flatMap { URL(fileURLWithPath: $0).lastPathComponent })

        return """
        tell application "Ghostty"
            if not (it is running) then return ""
            activate

            set targetWindow to missing value
            set targetTab to missing value
            set targetTerminal to missing value

            -- 1. Match by terminal ID (exact)
            if "\(terminalId)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (id of aTerminal as text) is "\(terminalId)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            -- 2. Match by cwd last directory name in tab title
            if targetTerminal is missing value and "\(cwdLastPart)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(cwdLastPart)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            -- 3. Match by working directory (prefix — agent cwd may be subdirectory)
            if targetTerminal is missing value and "\(workDir)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            set termCwd to (working directory of aTerminal as text)
                            if "\(workDir)" starts with termCwd or termCwd starts with "\(workDir)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            -- 4. Match by pane title (contains)
            if targetTerminal is missing value and "\(title)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(title)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            if targetTerminal is missing value then return ""

            -- Focus: activate window, select tab, focus terminal
            repeat 3 times
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay 0.05
                end if
                if targetTab is not missing value then
                    select tab targetTab
                    delay 0.05
                end if
                focus targetTerminal
                delay 0.1

                -- Verify focus landed on the right terminal
                if "\(terminalId)" is "" then return "matched"
                try
                    if (id of focused terminal of selected tab of front window as text) is "\(terminalId)" then
                        return "matched"
                    end if
                end try
            end repeat
        end tell
        return ""
        """
    }

    // MARK: - Terminal.app (TTY or title matching)

    private static func jumpToTerminalApp(_ terminal: TerminalInfo) {
        let tty = escapeAS(terminal.tty)
        let title = escapeAS(terminal.paneTitle)

        let script = """
        tell application "Terminal"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if "\(tty)" is not "" and (tty of aTab as text) is "\(tty)" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                    if "\(title)" is not "" and (custom title of aTab as text) contains "\(title)" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """

        let result = runAppleScript(script)
        if result != "matched" {
            if let tabIndex = terminal.tabIndex {
                runAppleScript("""
                tell application "Terminal"
                    activate
                    set selected tab of window 1 to tab \(tabIndex) of window 1
                end tell
                """)
            } else {
                activateApp(bundleId: "com.apple.Terminal")
            }
        }
    }

    // MARK: - VS Code / Cursor (workspace jump via CLI)

    private static func jumpToVSCodeFamily(bundleId: String, cli: String, terminal: TerminalInfo) {
        if let workDir = terminal.workingDirectory {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [cli, "-r", workDir]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return }
        }
        activateApp(bundleId: bundleId)
    }

    // MARK: - Helpers

    private static func activateApp(bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
        }
    }

    private static func activateApp(name: String) {
        let candidates = [
            "/Applications/\(name).app",
            "/Applications/Utilities/\(name).app",
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                return
            }
        }
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("[TerminalJumper] osascript launch failed: \(error)")
            return ""
        }

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if task.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            print("[TerminalJumper] AppleScript error: \(stderr)")
            return ""
        }

        return output
    }

    private static func escapeAS(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
