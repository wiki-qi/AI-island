import SwiftUI

/// Permission approval card — matches Open Vibe Island style
struct ApprovalView: View {
    let request: ApprovalRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: warning icon + tool name
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text(toolLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            // Command/description preview
            VStack(alignment: .leading, spacing: 8) {
                Text(request.description.isEmpty ? request.toolName : request.description)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)

                if let path = request.filePath, !path.isEmpty {
                    Text(path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.08, blue: 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.orange.opacity(0.18))
            )

            // Diff preview
            if let diff = request.diff {
                DiffPreview(diff: diff)
            }

            // Action buttons
            HStack(spacing: 8) {
                ActionButton(title: "No", kind: .secondary, action: onDeny)
                ActionButton(title: "Yes", kind: .warning, action: onApprove)
            }
        }
    }

    private var toolLabel: String {
        let name = request.toolName.lowercased()
        if name.contains("bash") || name.contains("exec") || name.contains("command") { return "Bash" }
        if name.contains("edit") || name.contains("write") || name.contains("patch") { return "Edit" }
        if name.contains("read") { return "Read" }
        if name.contains("ask") { return "Question" }
        return request.toolName
    }
}

// MARK: - Diff Preview

struct DiffPreview: View {
    let diff: DiffContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(diff.oldLines.prefix(5).enumerated()), id: \.offset) { _, line in
                Text("- \(line)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
            }
            ForEach(Array(diff.newLines.prefix(5).enumerated()), id: \.offset) { _, line in
                Text("+ \(line)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
            }
            HStack(spacing: 8) {
                Text("+\(diff.additions)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.green)
                Text("-\(diff.deletions)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Completion Card

struct CompletionCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                Text(promptLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("完成")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.29, green: 0.86, blue: 0.46).opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            // Summary
            Text(session.summary.isEmpty ? "Task completed." : session.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var promptLabel: String {
        if let first = session.messages.first(where: { $0.type == .userPrompt }) {
            return "You: \(first.content)"
        }
        return session.name
    }
}

// MARK: - Reusable button style

struct ActionButton: View {
    enum Kind { case primary, secondary, warning, danger }

    let title: String
    let kind: Kind
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .warning, .danger: return .white
        case .secondary: return .white.opacity(0.88)
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary: return Color(red: 0.26, green: 0.45, blue: 0.86)
        case .secondary: return Color.white.opacity(0.16)
        case .warning: return Color(red: 0.85, green: 0.55, blue: 0.15)
        case .danger: return Color(red: 0.82, green: 0.22, blue: 0.22)
        }
    }
}
