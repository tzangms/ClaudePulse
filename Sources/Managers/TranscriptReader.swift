import Foundation

/// Shared tail read for the JSONL transcripts Claude Code writes.
///
/// Transcripts reach tens of megabytes and everything Pulse wants — the last
/// usage report, the current title — is written repeatedly and lives near the
/// end, so only the tail is ever read.
enum TranscriptTail {
    static let defaultBytes = 512 * 1024

    /// The tail's whole lines, oldest first. The first line of a tail read is
    /// almost always a fragment, so it is dropped.
    static func lines(path: String, bytes: Int = defaultBytes) -> [Data] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return [] }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        var lines: [Data] = data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { Data($0) }
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}

/// Reads the name Claude Code gives a session.
///
/// Claude Code stores it as a `custom-title` record, rewritten as the title
/// changes, so the last one in the transcript is the current name. Older
/// transcripts carry a `summary` record instead, which serves the same purpose.
enum SessionTitleReader {

    static func read(transcriptPath: String) -> String? {
        title(in: TranscriptTail.lines(path: transcriptPath))
    }

    static func title(in lines: [Data]) -> String? {
        for line in lines.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            switch type {
            case "custom-title":
                if let title = clean(json["customTitle"]) { return title }
            case "summary":
                if let title = clean(json["summary"]) { return title }
            default:
                continue
            }
        }
        return nil
    }

    private static func clean(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
