import AppKit
import SwiftUI

struct ExpandedDetailView: View {
    let session: Session?
    let sessions: [Session]
    let onSelectSession: (String) -> Void
    let onOpenSession: (Session, Bool) -> Void
    private let settings = PanelSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sessions) { s in
                SessionRow(session: s, isSelected: s.id == session?.id)
                    .onTapGesture {
                        // Option-click always hands the session to Claude for Desktop.
                        let optionHeld = NSEvent.modifierFlags.contains(.option)
                        onSelectSession(s.id)
                        onOpenSession(s, optionHeld)
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 280 * settings.textSize.scale)
    }
}

struct SessionRow: View {
    let session: Session
    var isSelected: Bool = false
    private let settings = PanelSettings.shared
    @Environment(\.panelVisible) private var panelVisible

    @State private var isHovered = false

    var body: some View {
        let s = settings.textSize.scale
        HStack(spacing: 6) {
            Circle()
                .fill(rowStateColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(session.projectName)
                        .font(.system(size: 11 * s, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.6))
                        .lineLimit(1)
                    if !rowStateLabel.isEmpty {
                        Text(rowStateLabel)
                            .font(.system(size: 9 * s, weight: .medium))
                            .foregroundStyle(rowStateColor.opacity(0.7))
                    }
                }
                if let prompt = session.lastPrompt {
                    Text(prompt)
                        .font(.system(size: 10 * s))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            if isHovered {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 9 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .help(revealHelp)
            }
            if let context = session.contextWindow {
                UsageRing(
                    fraction: context.fraction,
                    diameter: 11 * s,
                    color: UsageTint.color(for: context.fraction, accent: settings.accentColor)
                )
                .help("Context window — \(context.summary)")
            }
            if session.isActive, panelVisible {
                TimelineView(.periodic(from: .now, by: 3)) { _ in
                    Text(session.formattedTime)
                        .font(.system(size: 10 * s, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            isSelected ? .white.opacity(0.08) : (isHovered ? .white.opacity(0.05) : .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(rowHelp)
    }

    /// The full path is the only way to tell two same-named folders apart, and
    /// it makes a stale or unexpected working directory obvious.
    private var rowHelp: String {
        var lines = [session.cwd ?? "(unknown directory)"]
        if let tool = session.lastToolName { lines.append("last tool: \(tool)") }
        lines.append("session \(session.id.prefix(8))")
        return lines.joined(separator: "\n")
    }

    private var revealHelp: String {
        "Click to reveal this session — Option-click to show it in Claude"
    }

    private var rowStateColor: Color {
        switch session.state {
        case .idle: return .gray
        case .working: return PanelSettings.shared.accentColor
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var rowStateLabel: String {
        switch session.state {
        case .idle: return ""
        case .working: return "working"
        case .waitingForUser: return "waiting"
        case .stale: return "stale"
        }
    }
}
