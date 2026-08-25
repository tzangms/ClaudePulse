import SwiftUI

/// A small filled ring, the way Claude's own context meter reads: a faint track
/// with an arc sweeping clockwise from the top.
struct UsageRing: View {
    let fraction: Double
    var diameter: CGFloat = 11
    var lineWidth: CGFloat = 2
    var color: Color = .white

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Colour ramp shared by the per-session ring and the global bars: the accent
/// colour until a window is worth worrying about, then amber, then red.
enum UsageTint {
    static func color(for fraction: Double, accent: Color) -> Color {
        switch fraction {
        case ..<0.7: return accent
        case ..<0.9: return .orange
        default: return .red
        }
    }
}

/// The account-wide limits, sized to sit in the panel's button row.
struct GlobalUsageView: View {
    let usage: UsageSnapshot
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        HStack(spacing: 8) {
            ForEach(windows, id: \.label) { entry in
                HStack(spacing: 3) {
                    UsageRing(
                        fraction: entry.window.fraction,
                        diameter: 9 * s,
                        lineWidth: 1.8,
                        color: UsageTint.color(for: entry.window.fraction, accent: settings.accentColor)
                    )
                    Text(entry.label)
                        .font(.system(size: 9 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(entry.window.percentText)
                        .font(.system(size: 9 * s, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .help(help(for: entry))
            }
        }
    }

    private struct Entry {
        let label: String
        let window: RateLimitWindow
    }

    /// Opus and Sonnet weekly windows only appear once they exist, so the row
    /// stays short on plans that do not have them.
    private var windows: [Entry] {
        var entries: [Entry] = []
        if let five = usage.fiveHour { entries.append(Entry(label: "5h", window: five)) }
        if let week = usage.sevenDay { entries.append(Entry(label: "wk", window: week)) }
        if let opus = usage.sevenDayOpus { entries.append(Entry(label: "op", window: opus)) }
        if let sonnet = usage.sevenDaySonnet { entries.append(Entry(label: "so", window: sonnet)) }
        return entries
    }

    private func help(for entry: Entry) -> String {
        let name: String
        switch entry.label {
        case "5h": name = "5-hour session limit"
        case "wk": name = "Weekly limit"
        case "op": name = "Weekly Opus limit"
        default: name = "Weekly Sonnet limit"
        }
        var text = "\(name) — \(entry.window.percentText) used"
        if let reset = entry.window.resetText() { text += "\n\(reset)" }
        // Readings come from samples taken minutes apart, so say how old this
        // one is rather than implying it is live.
        if let age = ageText { text += "\n\(age)" }
        return text
    }

    private var ageText: String? {
        let age = Date().timeIntervalSince(usage.updatedAt)
        guard age > 300 else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "as of \(formatter.string(from: usage.updatedAt))"
    }
}
