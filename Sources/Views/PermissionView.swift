import SwiftUI

/// Permission prompts held open by Pulse, with the buttons that answer them.
struct PermissionListView: View {
    let permissions: [PendingPermission]
    let sessionName: (String) -> String
    let onDecision: (PendingPermission, PermissionDecision) -> Void
    let onFocusSession: (String) -> Void
    private let settings = PanelSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(permissions) { permission in
                PermissionRow(
                    permission: permission,
                    projectName: sessionName(permission.sessionId),
                    onDecision: { onDecision(permission, $0) },
                    onFocusSession: { onFocusSession(permission.sessionId) }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(width: 280 * settings.textSize.scale)
    }
}

struct PermissionRow: View {
    let permission: PendingPermission
    let projectName: String
    let onDecision: (PermissionDecision) -> Void
    let onFocusSession: () -> Void
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9 * s, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(permission.toolName)
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundStyle(.white)
                Text(projectName)
                    .font(.system(size: 9 * s))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remaining(at: context.date))
                        .font(.system(size: 9 * s, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if !permission.detail.isEmpty {
                Text(permission.detail)
                    .font(.system(size: 10 * s, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 5) {
                let words = permission.vocabulary
                PermissionButton(title: words.allow, tint: settings.accentColor) {
                    onDecision(.allow)
                }
                if permission.canAllowAlways {
                    PermissionButton(title: "Allow all", tint: settings.accentColor.opacity(0.75)) {
                        onDecision(.allowAlways)
                    }
                }
                PermissionButton(title: words.deny, tint: .red.opacity(0.8), help: words.denyHelp) {
                    onDecision(.deny)
                }
                Spacer(minLength: 0)
                PermissionButton(
                    title: "Terminal",
                    tint: .white.opacity(0.25),
                    help: "Answer in the terminal instead"
                ) {
                    onDecision(.deferToTerminal)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 0.5)
        )
        // The buttons swallow their own clicks, so this only fires on the rest
        // of the card — going to look at the session should not answer for it.
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { onFocusSession() }
        .help("Click to reveal this session — the buttons answer without leaving Pulse")
    }

    private func remaining(at date: Date) -> String {
        let seconds = max(0, Int(permission.expiresAt.timeIntervalSince(date).rounded()))
        return "\(seconds)s"
    }
}

private struct PermissionButton: View {
    let title: String
    let tint: Color
    var help: String?
    let action: () -> Void

    @State private var hovered = false
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        Button(action: action) {
            Text(title)
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundStyle(.white.opacity(hovered ? 1.0 : 0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(hovered ? 0.55 : 0.3), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
        }
    }
}
