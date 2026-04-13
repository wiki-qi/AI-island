import SwiftUI
import AppKit

@main
enum NotchAgentApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: NotchWindowController?
    var statusItem: NSStatusItem?
    let sessionManager = SessionManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Prevent automatic termination
        ProcessInfo.processInfo.disableAutomaticTermination("NotchAgent must stay running")

        // Install bridge binary
        installBridge()

        // Socket server
        SocketServer.shared.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.sessionManager.handleSocketMessage(message)
            }
        }
        SocketServer.shared.start()

        // Configure hooks
        HookConfigurator.configureAll()

        // Create notch window
        setupNotchWindow()

        // Start session cleanup timer
        sessionManager.startCleanupTimer()

        // Menubar
        setupMenuBar()

        print("[NotchAgent] ✅ Launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        SocketServer.shared.stop()
    }

    private func setupNotchWindow() {
        let controller = NotchWindowController()
        let contentView = NotchContentView(
            sessionManager: sessionManager,
            windowController: controller
        )
        controller.show(rootView: contentView)
        self.windowController = controller
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "NotchAgent")
            if button.image == nil { button.title = "🏝️" }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "NotchAgent Running", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let reconfigItem = NSMenuItem(title: "Reconfigure Hooks", action: #selector(reconfigureHooks), keyEquivalent: "r")
        reconfigItem.target = self
        menu.addItem(reconfigItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NotchAgent", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func reconfigureHooks() {
        HookConfigurator.configureAll()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func installBridge() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".notch-agent/bin")
        let destPath = binDir.appendingPathComponent("notch-agent-bridge")

        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        // Find the NotchBridge binary next to our own executable
        if let execURL = Bundle.main.executableURL {
            let bridgeURL = execURL.deletingLastPathComponent().appendingPathComponent("NotchBridge")
            if fm.fileExists(atPath: bridgeURL.path) {
                try? fm.removeItem(at: destPath)
                try? fm.copyItem(at: bridgeURL, to: destPath)
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
                print("[NotchAgent] Bridge installed: \(destPath.path)")
                return
            }
        }

        // Fallback: check SPM build directory
        let spmBridge = home.appendingPathComponent("Documents/app/vibe/NotchAgent/.build/debug/NotchBridge")
        if fm.fileExists(atPath: spmBridge.path) {
            try? fm.removeItem(at: destPath)
            try? fm.copyItem(at: spmBridge, to: destPath)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
            print("[NotchAgent] Bridge installed from SPM build: \(destPath.path)")
        }
    }
}
