import Foundation

/// Reads Claude for Desktop's on-disk session records.
///
/// Layout: `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<uuid>.json`.
/// Each record carries its own `sessionId` (always `local_<uuid>`) and the
/// `cliSessionId` of the Claude Code session behind it. The two agree only for
/// sessions the app imported; a session started in the desktop app, or one that
/// was resumed, keeps a `sessionId` of its own.
///
/// A record file named `local_<cliSessionId>.json` is therefore *not* proof
/// that it is the session's live twin — it is just as likely to be the leftover
/// of an earlier import, holding a stale copy of the same transcript. Deciding
/// which record is live takes the whole set, not one filename.
enum ClaudeDesktopSessions {

    static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// The id of the desktop session currently running this Claude Code
    /// session, or nil when the desktop app is not running it at all.
    static func liveTwin(of cliSessionId: String, in store: URL? = nil) -> String? {
        guard isSafeSessionId(cliSessionId) else { return nil }
        let records = recordsClaiming(cliSessionId: cliSessionId, in: store ?? storeURL)
        guard let live = records.max(by: liveliness) else { return nil }
        return isSafeRouteComponent(live.sessionId) ? live.sessionId : nil
    }

    // MARK: - Records

    private struct Record {
        let sessionId: String
        let isArchived: Bool
        let lastActivity: Double
    }

    /// An archived session is never the live one; otherwise the most recently
    /// active record wins.
    private static func liveliness(_ a: Record, _ b: Record) -> Bool {
        if a.isArchived != b.isArchived { return a.isArchived }
        return a.lastActivity < b.lastActivity
    }

    private static func recordsClaiming(cliSessionId: String, in store: URL) -> [Record] {
        // Scanning the raw bytes first keeps this cheap: the store holds
        // hundreds of records totalling tens of megabytes, and only the handful
        // that name this session are worth decoding.
        let needles = [
            Data("\"cliSessionId\":\"\(cliSessionId)\"".utf8),
            Data("\"cliSessionId\": \"\(cliSessionId)\"".utf8),
        ]

        var found: [Record] = []
        for directory in accountDirectories(in: store) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
                guard needles.contains(where: { data.range(of: $0) != nil }) else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["cliSessionId"] as? String == cliSessionId,
                      let sessionId = json["sessionId"] as? String else { continue }

                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate?.timeIntervalSince1970 ?? 0
                found.append(Record(
                    sessionId: sessionId,
                    isArchived: json["isArchived"] as? Bool ?? false,
                    lastActivity: timestamp(json["lastActivityAt"])
                        ?? timestamp(json["lastFocusedAt"])
                        ?? modified
                ))
            }
        }
        return found
    }

    /// The app writes these as epoch milliseconds, but has also used ISO-8601.
    private static func timestamp(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let text = value as? String {
            if let number = Double(text) { return number }
            return ISO8601DateFormatter().date(from: text)?.timeIntervalSince1970
        }
        return nil
    }

    /// The store nests one directory per account, then per organization.
    private static func accountDirectories(in store: URL) -> [URL] {
        let fm = FileManager.default
        let accounts = (try? fm.contentsOfDirectory(at: store, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return accounts.flatMap { account in
            (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        }
    }

    /// Session ids reach this code straight from a hook payload, so keep them
    /// out of path construction unless they look like the ids Claude Code emits.
    private static func isSafeSessionId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }

    /// Desktop ids come off disk and end up in a URL path, so allow only the
    /// characters the app's own ids use.
    private static func isSafeRouteComponent(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}
