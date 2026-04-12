import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Collapse the notch panel first
        SessionManager.shared.notchClose()

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "NotchAgent 设置"
        window.styleMask = [.titled, .closable]
        window.level = .statusBar + 9
        window.setContentSize(NSSize(width: 450, height: 380))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
