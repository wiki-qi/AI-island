import SwiftUI

// MARK: - Animations

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
private let closeAnimation = Animation.smooth(duration: 0.3)

struct NotchContentView: View {
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var windowController: NotchWindowController
    @State private var isHovering = false

    @AppStorage("soundEnabled") private var soundEnabled = true

    private var isOpened: Bool { sessionManager.notchStatus == .opened }

    private var notchWidth: CGFloat { windowController.notchWidth }
    private var notchHeight: CGFloat { windowController.notchHeight }

    // Closed surface width: notch + expansion for session indicators
    private var closedWidth: CGFloat {
        guard sessionManager.activeSessions.count > 0 else { return notchWidth }
        let sideWidth = max(0, notchHeight - 12) + 10
        let countBadgeWidth: CGFloat = 30
        let hasAttention = sessionManager.activeSessions.contains { $0.phase.requiresAttention }
        let leftWidth = sideWidth + 8 + (hasAttention ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth)
        return notchWidth + leftWidth + rightWidth + 16 + (hasAttention ? 6 : 0)
    }

    private var currentWidth: CGFloat {
        isOpened ? windowController.openedWidth : closedWidth
    }
    private var currentHeight: CGFloat {
        isOpened ? windowController.openedHeight : notchHeight
    }

    private var surfaceShape: NotchShape {
        NotchShape(
            topCornerRadius: isOpened ? NotchShape.openedTopRadius : NotchShape.closedTopRadius,
            bottomCornerRadius: isOpened ? NotchShape.openedBottomRadius : NotchShape.closedBottomRadius
        )
    }

    private var notchAnimation: Animation {
        isOpened ? openAnimation : closeAnimation
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                Color.clear

                // The island surface
                islandSurface
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Island surface

    private var islandSurface: some View {
        let insetH: CGFloat = isOpened ? 14 : 0
        let insetB: CGFloat = isOpened ? 14 : 0
        let surfaceW = currentWidth + insetH * 2
        let surfaceH = currentHeight + insetB

        return ZStack(alignment: .top) {
            // Black fill
            surfaceShape
                .fill(Color.black)
                .frame(width: surfaceW, height: surfaceH)

            // Content
            VStack(spacing: 0) {
                headerRow
                    .frame(height: notchHeight)

                if isOpened {
                    openedContent
                        .frame(width: currentWidth - 24)
                        .frame(maxHeight: currentHeight - notchHeight - 12, alignment: .top)
                        .clipped()
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .padding(.horizontal, insetH)
            .padding(.bottom, insetB)
            .clipShape(surfaceShape)

            // Top black strip to blend with physical notch
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.horizontal, isOpened ? NotchShape.openedTopRadius : NotchShape.closedTopRadius)

            // Border
            surfaceShape
                .stroke(Color.white.opacity(isOpened ? 0.07 : 0.04), lineWidth: 1)
                .frame(width: surfaceW, height: surfaceH)
        }
        .frame(width: surfaceW, height: surfaceH, alignment: .top)
        .scaleEffect(isOpened ? 1 : (isHovering ? 1.03 : 1), anchor: .top)
        .shadow(color: .black.opacity(isOpened ? 0.5 : 0), radius: 16)
        .animation(notchAnimation, value: sessionManager.notchStatus)
        .animation(.smooth, value: closedWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isOpened {
                sessionManager.notchOpen()
                windowController.setInteractive(true)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
            if hovering && !isOpened {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if isHovering && !isOpened {
                        sessionManager.notchOpen()
                        windowController.setInteractive(true)
                    }
                }
            } else if !hovering && isOpened {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if !isHovering && isOpened {
                        sessionManager.notchClose()
                        windowController.panel.ignoresMouseEvents = true
                    }
                }
            }
        }
    }

    // MARK: - Header row (shared closed/opened)

    @ViewBuilder
    private var headerRow: some View {
        if isOpened {
            openedHeader
        } else {
            closedHeader
        }
    }

    private var closedHeader: some View {
        let hasAttention = sessionManager.activeSessions.contains { $0.phase.requiresAttention }

        return HStack(spacing: 0) {
            if sessionManager.activeSessions.count > 0 {
                // Left: pixel icon + attention indicator (OUTSIDE notch)
                HStack(spacing: 4) {
                    pixelAgent
                    if hasAttention {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(scoutTint)
                    }
                }
                .padding(.top, NotchShape.closedTopRadius)

                // Center: full notch width gap
                Spacer()
                    .frame(width: notchWidth)

                // Right: session count badge (OUTSIDE notch)
                Text("\(sessionManager.activeSessions.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(scoutTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(white: 0.14), in: Capsule())
                    .padding(.top, NotchShape.closedTopRadius)
            } else {
                Color.clear.frame(width: notchWidth - 20)
            }
        }
        .frame(height: notchHeight)
    }

    private var openedHeader: some View {
        HStack(spacing: 8) {
            if sessionManager.activeSessions.count > 0 {
                Text("\(sessionManager.activeSessions.count) 个会话")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }

            Spacer()

            // Sound toggle
            headerButton(
                icon: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                tint: soundEnabled ? .white.opacity(0.62) : .orange.opacity(0.92)
            ) { soundEnabled.toggle() }

            // Settings
            headerButton(icon: "gearshape.fill", tint: .white.opacity(0.62)) {
                SettingsWindowController.shared.show()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }

    private func headerButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Opened content

    private var openedContent: some View {
        VStack(spacing: 0) {
            if sessionManager.activeSessions.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundColor(.gray.opacity(0.6))
                    Text("小岛等待中")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray.opacity(0.8))
                    Text("重启终端或开启一个新会话")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.5))
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(sessionManager.activeSessions) { session in
                            SessionRowView(session: session, sessionManager: sessionManager)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Pixel agent icon

    private var scoutTint: Color {
        let sessions = sessionManager.activeSessions
        if sessions.contains(where: { $0.phase == .waitingForApproval }) {
            return Color(red: 1.0, green: 0.71, blue: 0.28)   // #FFB547 orange
        }
        if sessions.contains(where: { $0.phase == .waitingForAnswer }) {
            return Color(red: 1.0, green: 0.85, blue: 0.35)   // #FFD95A yellow
        }
        if sessions.contains(where: { $0.phase == .running }) {
            return Color(red: 0.43, green: 0.62, blue: 1.0)   // #6E9FFF blue
        }
        if !sessions.isEmpty {
            return Color(red: 0.26, green: 0.91, blue: 0.42)  // #42E86B green
        }
        return Color.white.opacity(0.4)
    }

    private var hasClosedActivity: Bool {
        sessionManager.activeSessions.contains { $0.phase == .running || $0.phase.requiresAttention }
    }

    private var pixelAgent: some View {
        // Walking animation: 2 frames alternating legs
        let frame1 = [
            "..B..B..",
            "..BBBB..",
            ".BHHHHB.",
            "BBHEHEBB",
            ".BHHHHB.",
            "..BBBB..",
            "..B..B..",
            ".B....B.",
        ]
        let frame2 = [
            "..B..B..",
            "..BBBB..",
            ".BHHHHB.",
            "BBHEHEBB",
            ".BHHHHB.",
            "..BBBB..",
            ".B....B.",
            "B......B",
        ]
        let frames = [frame1, frame2]
        let px: CGFloat = 1.6
        let speed: TimeInterval = hasClosedActivity ? 0.2 : 0.6

        return TimelineView(.animation(minimumInterval: speed, paused: false)) { context in
            let idx = Int(context.date.timeIntervalSinceReferenceDate / speed) % frames.count
            let pattern = frames[idx]

            VStack(spacing: 0) {
                ForEach(0..<pattern.count, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let ch = Array(pattern[row])[col]
                            Rectangle()
                                .fill(pixelColor(for: ch))
                                .frame(width: px, height: px)
                        }
                    }
                }
            }
        }
    }

    private func pixelColor(for ch: Character) -> Color {
        switch ch {
        case "B": return scoutTint
        case "H": return scoutTint.opacity(0.7)
        case "E": return Color.black.opacity(0.72)
        default: return .clear
        }
    }
}
