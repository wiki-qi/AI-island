import Cocoa
import SwiftUI

// MARK: - NSScreen extension for notch detection

extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }
        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var islandClosedHeight: CGFloat {
        if safeAreaInsets.top > 0 { return safeAreaInsets.top }
        return max(0, frame.maxY - visibleFrame.maxY)
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }
}

// MARK: - NotchPanel (NSPanel subclass)

class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchHostingView (mouse passthrough via hitTest)

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var panelController: NotchWindowController?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    /// Only respond to mouse in the content area, pass through everywhere else
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = panelController,
              let contentRect = controller.contentRect(in: bounds) else {
            return nil
        }
        guard contentRect.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - NotchWindowController

@MainActor
final class NotchWindowController: ObservableObject {
    let panel: NotchPanel
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    // Panel is always at opened size — SwiftUI handles visual transitions
    let openedWidth: CGFloat = 680
    let openedHeight: CGFloat = 420
    private let shadowInsetH: CGFloat = 18
    private let shadowInsetB: CGFloat = 22

    var notchRect: NSRect {
        let x = screen.frame.midX - notchWidth / 2
        let y = screen.frame.maxY - notchHeight
        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    init() {
        let scr = NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main ?? NSScreen.screens[0]
        self.screen = scr
        self.notchWidth = scr.notchSize.width
        self.notchHeight = scr.islandClosedHeight

        // Window always at max size, centered on notch
        let totalW = openedWidth + shadowInsetH * 2
        let totalH = openedHeight + shadowInsetB
        let x = scr.frame.midX - totalW / 2
        let y = scr.frame.maxY - totalH

        self.panel = NotchPanel(
            contentRect: NSRect(x: x, y: y, width: totalW, height: totalH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
    }

    func show(rootView: some View) {
        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.panelController = self
        panel.contentView = hostingView
        panel.orderFrontRegardless()
    }

    /// The visible content rect within the hosting view bounds (excluding shadow insets)
    func contentRect(in bounds: NSRect) -> NSRect? {
        NSRect(
            x: shadowInsetH,
            y: shadowInsetB,
            width: max(0, bounds.width - shadowInsetH * 2),
            height: max(0, bounds.height - shadowInsetB)
        )
    }

    func setInteractive(_ interactive: Bool) {
        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive
        if interactive {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
