import SwiftUI

struct SessionRowView: View {
    let session: AgentSession
    @ObservedObject var sessionManager: SessionManager
    @State private var isExpanded = false
    @State private var isHighlighted = false

    private var isActionable: Bool {
        session.phase.requiresAttention || session.phase == .completed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 14) {
                // Status dot
                Circle()
                    .fill(statusTint)
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    // Title + badges
                    HStack(alignment: .top, spacing: 12) {
                        Text(session.name)
                            .font(.system(size: isActionable ? 15 : 14, weight: .semibold))
                            .foregroundStyle(session.phase == .completed ? .white.opacity(0.78) : .white)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            badge(session.agentType.rawValue)
                            badge(session.elapsed)
                        }
                    }

                    // Summary line
                    if !session.summary.isEmpty {
                        Text(session.summary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    // Activity line (current tool)
                    if session.phase == .running, let last = session.messages.last {
                        Text(last.content)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusTint.opacity(0.94))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isActionable ? 14 : 14)

            // Actionable body
            if isExpanded || isActionable {
                actionableBody
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(isActionable ? 0.06 : 0.05) : Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .strokeBorder(borderColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            if isActionable {
                // Already showing action body
            } else if !session.messages.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } else {
                TerminalJumper.jump(to: session.terminal)
            }
        }
        .onHover { isHighlighted = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    // MARK: - Actionable body

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            if let approval = session.pendingApproval {
                ApprovalView(
                    request: approval,
                    onApprove: { sessionManager.approve(sessionId: session.id) },
                    onDeny: { sessionManager.deny(sessionId: session.id) }
                )
            }

        case .waitingForAnswer:
            if let approval = session.pendingApproval {
                // Question prompt — show options
                VStack(alignment: .leading, spacing: 12) {
                    Text(approval.description)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.96))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ActionButton(title: "Yes", kind: .primary) {
                            sessionManager.approve(sessionId: session.id)
                        }
                        ActionButton(title: "No", kind: .secondary) {
                            sessionManager.deny(sessionId: session.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.yellow.opacity(0.12))
                )
            }

        case .completed:
            CompletionCard(session: session)

        case .running:
            // Expanded detail — recent messages
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.messages.suffix(5)) { msg in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: iconForMessage(msg.type))
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                                .frame(width: 12)
                            Text(msg.content)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                    }

                    Button(action: { TerminalJumper.jump(to: session.terminal) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 9))
                            Text("跳转到终端")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(.cyan)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private var statusTint: Color {
        switch session.phase {
        case .waitingForApproval: return .orange.opacity(0.94)
        case .waitingForAnswer: return .yellow.opacity(0.96)
        case .running: return Color(red: 0.34, green: 0.61, blue: 0.99)
        case .completed: return Color(red: 0.29, green: 0.86, blue: 0.46)
        }
    }

    private var borderColor: Color {
        if isActionable {
            return statusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? .white.opacity(0.24) : .white.opacity(0.04)
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(session.phase == .completed ? .white.opacity(0.42) : .white.opacity(0.56))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }

    private func iconForMessage(_ type: MessageType) -> String {
        switch type {
        case .userPrompt: return "person.fill"
        case .agentThinking: return "brain"
        case .toolUse: return "wrench"
        case .toolResult: return "checkmark"
        case .completion: return "flag.fill"
        case .error: return "xmark.circle"
        }
    }
}
