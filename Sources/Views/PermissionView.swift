import SwiftUI

/// Permission prompts held open by Pulse, with the buttons that answer them.
struct PermissionListView: View {
    let permissions: [PendingPermission]
    let sessionName: (String) -> String
    /// False for sessions Claude for Desktop runs: there is no terminal prompt
    /// waiting behind Pulse for them, so offering to defer to one is a dead end.
    let offersTerminalHandoff: (String) -> Bool
    let onDecision: (PendingPermission, PermissionDecision) -> Void
    let onFocusSession: (String) -> Void
    private let settings = PanelSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(permissions) { permission in
                PermissionRow(
                    permission: permission,
                    projectName: sessionName(permission.sessionId),
                    offersTerminalHandoff: offersTerminalHandoff(permission.sessionId),
                    onDecision: { onDecision(permission, $0) },
                    onFocusSession: { onFocusSession(permission.sessionId) }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(width: settings.contentWidth)
    }
}

struct PermissionRow: View {
    let permission: PendingPermission
    let projectName: String
    var offersTerminalHandoff: Bool = true
    let onDecision: (PermissionDecision) -> Void
    let onFocusSession: () -> Void
    private let settings = PanelSettings.shared

    /// Set by the row's own chevron, for the one prompt that needs more room
    /// than the size setting gives every prompt.
    @State private var expanded = false

    /// The size setting is the floor; expanding a single row lifts it.
    private var detailSize: ActionDetail {
        expanded ? .full : settings.actionDetail
    }

    private var detailText: String {
        detailSize.showsWholeInput ? permission.fullDetail : permission.detail
    }

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
                if permission.hasMoreDetail || settings.actionDetail != .full {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9 * s, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 16, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Show less" : "Show everything this call would do")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remaining(at: context.date))
                        .font(.system(size: 9 * s, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if !detailText.isEmpty {
                detailView(text: detailText, scale: s)
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
                if offersTerminalHandoff {
                    PermissionButton(
                        title: "Terminal",
                        tint: .white.opacity(0.25),
                        help: "Answer in the terminal instead"
                    ) {
                        onDecision(.deferToTerminal)
                    }
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

    /// A compact prompt keeps its one-line summary; the larger sizes wrap and
    /// let the text run to the line budget the size setting allows.
    @ViewBuilder
    private func detailView(text: String, scale s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10 * s, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
            .textSelection(.enabled)
            .lineLimit(detailSize.lineLimit)
            .truncationMode(detailSize == .compact ? .middle : .tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
