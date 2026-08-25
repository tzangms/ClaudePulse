import Foundation

/// How full a session's context window is.
struct ContextWindow: Equatable {
    var usedTokens: Int
    var size: Int

    var fraction: Double {
        guard size > 0 else { return 0 }
        return min(1, max(0, Double(usedTokens) / Double(size)))
    }

    var percentText: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Compact token counts, the way Claude Code writes them: `18k`, `756k`, `1.2M`.
    static func abbreviate(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000: return "\(tokens)"
        case ..<1_000_000: return "\(Int((Double(tokens) / 1_000).rounded()))k"
        default:
            let millions = Double(tokens) / 1_000_000
            return millions < 10
                ? String(format: "%.1fM", millions)
                : "\(Int(millions.rounded()))M"
        }
    }

    var summary: String {
        "\(Self.abbreviate(usedTokens)) / \(Self.abbreviate(size)) (\(percentText))"
    }
}

/// One of Claude Code's rate limit windows.
struct RateLimitWindow: Equatable {
    var usedPercentage: Double
    var resetsAt: Date?

    var fraction: Double { min(1, max(0, usedPercentage / 100)) }

    var percentText: String { "\(Int(usedPercentage.rounded()))%" }

    /// "resets in 2h 15m", or nil when the reset time is unknown or past.
    func resetText(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "resets in \(days)d \(hours % 24)h"
        }
        return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
    }
}

/// The account-wide limits, as last reported by Claude Code's status line.
struct UsageSnapshot: Equatable {
    var fiveHour: RateLimitWindow?
    var sevenDay: RateLimitWindow?
    var sevenDayOpus: RateLimitWindow?
    var sevenDaySonnet: RateLimitWindow?
    var updatedAt: Date

    var isEmpty: Bool {
        fiveHour == nil && sevenDay == nil && sevenDayOpus == nil && sevenDaySonnet == nil
    }

    // MARK: - Persistence

    /// Claude Code only reports limits while it is rendering a status line, so
    /// a freshly launched Pulse would show nothing until the next session did
    /// something. The last reading is kept so the panel is populated at launch.
    private static let defaultsKey = "usageSnapshot"

    func persist(to defaults: UserDefaults = .standard) {
        var values: [String: Any] = ["updatedAt": updatedAt.timeIntervalSince1970]
        for (key, window) in [
            "fiveHour": fiveHour, "sevenDay": sevenDay,
            "sevenDayOpus": sevenDayOpus, "sevenDaySonnet": sevenDaySonnet,
        ] {
            guard let window else { continue }
            var encoded: [String: Any] = ["usedPercentage": window.usedPercentage]
            if let resetsAt = window.resetsAt {
                encoded["resetsAt"] = resetsAt.timeIntervalSince1970
            }
            values[key] = encoded
        }
        defaults.set(values, forKey: Self.defaultsKey)
    }

    /// Readings older than a day describe windows that have almost certainly
    /// rolled over, so they are dropped rather than shown as current.
    static func restore(from defaults: UserDefaults = .standard, now: Date = Date()) -> UsageSnapshot? {
        guard let values = defaults.dictionary(forKey: defaultsKey),
              let updated = values["updatedAt"] as? TimeInterval else { return nil }
        let updatedAt = Date(timeIntervalSince1970: updated)
        guard now.timeIntervalSince(updatedAt) < 24 * 3600 else { return nil }

        func window(_ key: String) -> RateLimitWindow? {
            guard let encoded = values[key] as? [String: Any],
                  let used = encoded["usedPercentage"] as? Double else { return nil }
            let resets = (encoded["resetsAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            return RateLimitWindow(usedPercentage: used, resetsAt: resets)
        }

        let snapshot = UsageSnapshot(
            fiveHour: window("fiveHour"),
            sevenDay: window("sevenDay"),
            sevenDayOpus: window("sevenDayOpus"),
            sevenDaySonnet: window("sevenDaySonnet"),
            updatedAt: updatedAt
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    /// The window closest to running out — what a one-glance readout should show.
    var mostUsed: (label: String, window: RateLimitWindow)? {
        let candidates: [(String, RateLimitWindow?)] = [
            ("5h", fiveHour),
            ("week", sevenDay),
            ("week (Opus)", sevenDayOpus),
            ("week (Sonnet)", sevenDaySonnet),
        ]
        return candidates
            .compactMap { label, window in window.map { (label, $0) } }
            .max { $0.1.usedPercentage < $1.1.usedPercentage }
    }
}
