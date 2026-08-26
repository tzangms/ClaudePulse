import SwiftUI

// Claude AI logo path (from Bootstrap Icons)
struct ClaudeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width / 16
        let h = rect.height / 16

        // Scaled version of the Bootstrap Icons Claude path
        path.move(to: CGPoint(x: 3.127 * w, y: 10.604 * h))
        path.addLine(to: CGPoint(x: 6.262 * w, y: 8.844 * h))
        path.addLine(to: CGPoint(x: 6.315 * w, y: 8.691 * h))
        path.addLine(to: CGPoint(x: 6.262 * w, y: 8.606 * h))
        path.addLine(to: CGPoint(x: 6.11 * w, y: 8.606 * h))
        path.addLine(to: CGPoint(x: 5.585 * w, y: 8.574 * h))
        path.addLine(to: CGPoint(x: 3.794 * w, y: 8.526 * h))
        path.addLine(to: CGPoint(x: 2.24 * w, y: 8.461 * h))
        path.addLine(to: CGPoint(x: 0.735 * w, y: 8.381 * h))
        path.addLine(to: CGPoint(x: 0.355 * w, y: 8.3 * h))
        path.addLine(to: CGPoint(x: 0 * w, y: 7.832 * h))
        path.addLine(to: CGPoint(x: 0.036 * w, y: 7.598 * h))
        path.addLine(to: CGPoint(x: 0.356 * w, y: 7.384 * h))
        path.addLine(to: CGPoint(x: 0.811 * w, y: 7.424 * h))
        path.addLine(to: CGPoint(x: 1.82 * w, y: 7.493 * h))
        path.addLine(to: CGPoint(x: 3.333 * w, y: 7.598 * h))
        path.addLine(to: CGPoint(x: 4.43 * w, y: 7.662 * h))
        path.addLine(to: CGPoint(x: 6.056 * w, y: 7.832 * h))
        path.addLine(to: CGPoint(x: 6.315 * w, y: 7.832 * h))
        path.addLine(to: CGPoint(x: 6.351 * w, y: 7.727 * h))
        path.addLine(to: CGPoint(x: 6.262 * w, y: 7.662 * h))
        path.addLine(to: CGPoint(x: 6.194 * w, y: 7.598 * h))

        return path
    }
}

struct CapsuleView: View {
    let session: Session?
    let sessionCount: Int
    let activeCount: Int
    private let settings = PanelSettings.shared
    @Environment(\.panelVisible) private var panelVisible

    var body: some View {
        let s = settings.textSize.scale
        HStack(spacing: 8) {
            claudeIconView
                .frame(width: 16, height: 16)

            if let session = session {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.displayName)
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let folder = session.subtitleName {
                        Text(folder)
                            .font(.system(size: 9 * s))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // A word like "Working..." costs more width than the state is
                // worth while the panel is collapsed; the glyph says the same.
                SessionStateGlyph(state: session.state, scale: s)
                    .help(statusText)
            } else {
                Text("Pulse")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            if let session = session, session.isActive, panelVisible, settings.showSessionDuration {
                TimelineView(.periodic(from: .now, by: 3)) { _ in
                    Text(session.formattedTime)
                        .font(.system(size: 11 * s, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if sessionCount > 1 {
                HStack(spacing: 2) {
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 10 * s, weight: .bold, design: .rounded))
                            .foregroundStyle(settings.accentColor)
                    }
                    if activeCount > 0 && activeCount < sessionCount {
                        Text("/")
                            .font(.system(size: 9 * s, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text("\(sessionCount)")
                        .font(.system(size: 10 * s, weight: activeCount > 0 ? .medium : .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(activeCount > 0 ? 0.5 : 0.8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .frame(width: settings.contentWidth, height: 36 * s)
    }

    @ViewBuilder
    private var claudeIconView: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch session?.state ?? .idle {
        case .idle: return .gray
        case .working: return PanelSettings.shared.accentColor
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var statusText: String {
        switch session?.state ?? .idle {
        case .idle: return "Idle"
        case .working: return "Working..."
        case .waitingForUser: return "Waiting"
        case .stale: return "Stale"
        }
    }
}



/// The collapsed capsule's state indicator: an animated glyph rather than a
/// word, because the capsule has no width to spare.
struct SessionStateGlyph: View {
    let state: SessionState
    var scale: CGFloat = 1
    @Environment(\.panelVisible) private var panelVisible
    private let settings = PanelSettings.shared

    var body: some View {
        Group {
            switch state {
            case .working:
                // Dots filling left to right — the same reading as a spinner,
                // in a glyph that costs one character of width.
                animated(Image(systemName: "ellipsis"), effect: .variableColor.iterative)
            case .waitingForUser:
                animated(Image(systemName: "hand.raised.fill"), effect: .pulse)
            case .idle:
                Image(systemName: "circle.fill")
                    .font(.system(size: 5 * scale))
            case .stale:
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 9 * scale))
            }
        }
        .foregroundStyle(color)
        .frame(width: 14 * scale, alignment: .center)
    }

    /// Symbol animation is only worth running while the panel is on screen.
    @ViewBuilder
    private func animated(_ image: Image, effect: some IndefiniteSymbolEffect & SymbolEffect) -> some View {
        image
            .font(.system(size: 11 * scale, weight: .semibold))
            .symbolEffect(effect, isActive: panelVisible)
    }

    private var color: Color {
        switch state {
        case .idle: return .gray
        case .working: return settings.accentColor
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }
}
