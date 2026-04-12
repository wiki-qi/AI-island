import Foundation
import AppKit

/// Handles jumping to the correct terminal window/tab/pane
struct TerminalJumper {

    static func jump(to terminal: TerminalInfo) {
        switch terminal.app {
        case .iterm2:
            jumpToITerm2(terminal)
        case .ghostty:
            jumpToGhostty(terminal)
        case .terminal:
            jumpToTerminalApp(terminal)
        case .warp:
            activateApp(bundleId: "dev.warp.Warp-Stable")
        case .vscode:
            activateApp(bundleId: "com.microsoft.VSCode")
        case .cursor:
            activateApp(bundleId: "com.todesktop.230313mzl4w4u92")
        default:
            activateApp(name: terminal.app.rawValue)
        }
    }

    // MARK: - iTerm2 (AppleScript for precise tab/pane)

    private static func jumpToITerm2(_ terminal: TerminalInfo) {
        var script = "tell application \"iTerm2\" to activate"
        if let windowId = terminal.windowId, let tabIndex = terminal.tabIndex {
            script = """
            tell application "iTerm2"
                activate
                tell window id \(windowId)
                    select tab \(tabIndex)
                end tell
            end tell
            """
        }
        runAppleScript(script)
    }

    // MARK: - Ghostty

    private static func jumpToGhostty(_ terminal: TerminalInfo) {
        activateApp(bundleId: "com.mitchellh.ghostty")
        // Ghostty 1.3+ supports focus via CLI
        if let paneId = terminal.paneId {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ghostty")
            process.arguments = ["+focus", "--surface-id", paneId]
            try? process.run()
        }
    }

    // MARK: - Terminal.app

    private static func jumpToTerminalApp(_ terminal: TerminalInfo) {
        var script = "tell application \"Terminal\" to activate"
        if let tabIndex = terminal.tabIndex {
            script = """
            tell application "Terminal"
                activate
                set selected tab of window 1 to tab \(tabIndex) of window 1
            end tell
            """
        }
        runAppleScript(script)
    }

    // MARK: - Helpers

    private static func activateApp(bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
        }
    }

    private static func activateApp(name: String) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    private static func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                print("[TerminalJumper] AppleScript error: \(error)")
            }
        }
    }
}
