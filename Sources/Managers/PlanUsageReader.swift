import Foundation

/// Reads the usage history Claude for Desktop keeps on disk.
///
/// Claude Code reports rate limits only to its terminal status line, which
/// never runs for sessions hosted by Claude for Desktop — they have no REPL.
/// The desktop app records the same limits itself, sampling them every few
/// minutes into `plan-usage-history.json`, so that file is the reading that
/// matches what the app displays.
struct PlanUsageReader {
    var path: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

    /// A reading older than this describes windows that have moved on — the
    /// shortest window is five hours, and the app stops sampling when it quits.
    static let maximumAge: TimeInterval = 6 * 3600

    /// Short keys the desktop app writes, in the order it declares them.
    private enum Key {
        static let fiveHour = "fh"
        static let sevenDay = "sd"
        static let sevenDayOpus = "so"
        static let sevenDaySonnet = "sn"
    }

    func read(now: Date = Date()) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: path, options: .mappedIfSafe),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]] else { return nil }

        // Samples are appended in order, but the newest is what matters and
        // trusting the order is not worth a wrong number.
        guard let latest = samples.max(by: { timestamp($0) < timestamp($1) }),
              let milliseconds = latest["t"] as? Double,
              let values = latest["u"] as? [String: Any] else { return nil }

        let sampledAt = Date(timeIntervalSince1970: milliseconds / 1_000)
        guard now.timeIntervalSince(sampledAt) < Self.maximumAge else { return nil }

        func window(_ key: String) -> RateLimitWindow? {
            guard let percentage = values[key] as? Double else { return nil }
            // Reset times are not part of the history, only utilisation.
            return RateLimitWindow(usedPercentage: percentage, resetsAt: nil)
        }

        let snapshot = UsageSnapshot(
            fiveHour: window(Key.fiveHour),
            sevenDay: window(Key.sevenDay),
            sevenDayOpus: window(Key.sevenDayOpus),
            sevenDaySonnet: window(Key.sevenDaySonnet),
            updatedAt: sampledAt
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private func timestamp(_ sample: [String: Any]) -> Double {
        sample["t"] as? Double ?? 0
    }

    /// When the file last changed, so it is only re-parsed after the desktop
    /// app appends a sample.
    func modifiedAt() -> Date? {
        try? path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
