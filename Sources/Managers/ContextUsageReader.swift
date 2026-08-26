import Foundation

/// Reads a session's context usage out of its transcript.
///
/// This is the fallback for sessions whose status line has not reported yet —
/// the status line is authoritative because it carries the window size, which
/// Claude Code derives from the model, betas and env overrides. From a
/// transcript we can only read what was actually used and infer the size.
enum ContextUsageReader {

    /// Transcripts reach tens of megabytes, and the reading we want is at the
    /// very end, so only the tail is read.
    static let tailBytes = TranscriptTail.defaultBytes

    static func read(transcriptPath: String) -> ContextWindow? {
        read(lines: TranscriptTail.lines(path: transcriptPath))
    }

    /// Same reading from a tail that has already been read, so a refresh can
    /// pull the context and the session title out of one pass over the file.
    static func read(lines: [Data]) -> ContextWindow? {
        guard let usage = lastAssistantUsage(in: lines) else { return nil }
        let used = usage.inputTokens + usage.cacheCreationTokens + usage.cacheReadTokens
        guard used > 0 else { return nil }
        return ContextWindow(usedTokens: used, size: windowSize(model: usage.model, used: used))
    }

    // MARK: - Window size

    /// Models that Claude Code gives a million-token window.
    private static let millionTokenModels = ["opus-5", "sonnet-5", "fable-5"]

    static func windowSize(model: String?, used: Int) -> Int {
        // A reading larger than the standard window is proof on its own, and
        // covers models this table has not heard of yet.
        if used > 200_000 { return 1_000_000 }
        let name = (model ?? "").lowercased()
        return millionTokenModels.contains(where: name.contains) ? 1_000_000 : 200_000
    }

    // MARK: - Transcript

    private struct Usage {
        var inputTokens = 0
        var cacheCreationTokens = 0
        var cacheReadTokens = 0
        var model: String?
    }

    /// The last assistant turn's usage is the current context: each request
    /// re-sends the whole conversation, so its input counts describe the window
    /// as it stands — including after a compaction, which shrinks it again.
    private static func lastAssistantUsage(in lines: [Data]) -> Usage? {
        for line in lines.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            return Usage(
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                model: message["model"] as? String
            )
        }
        return nil
    }
}
