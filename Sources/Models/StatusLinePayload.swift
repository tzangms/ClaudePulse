import Foundation

/// The JSON Claude Code pipes to a `statusLine` command.
///
/// It is the only place Claude Code reports account-wide rate limits, and it
/// carries an authoritative context window reading — including the window size,
/// which cannot be derived reliably from a transcript alone.
struct StatusLinePayload: Decodable {
    let sessionId: String?
    let contextWindow: ContextWindowPayload?
    let rateLimits: RateLimitsPayload?
    let model: ModelPayload?

    struct ModelPayload: Decodable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    struct ContextWindowPayload: Decodable {
        let totalInputTokens: Int?
        let contextWindowSize: Int?

        enum CodingKeys: String, CodingKey {
            case totalInputTokens = "total_input_tokens"
            case contextWindowSize = "context_window_size"
        }
    }

    struct WindowPayload: Decodable {
        let usedPercentage: Double?
        let resetsAt: ResetTimestamp?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    struct RateLimitsPayload: Decodable {
        let fiveHour: WindowPayload?
        let sevenDay: WindowPayload?
        let sevenDayOpus: WindowPayload?
        let sevenDaySonnet: WindowPayload?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
        }
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
        case model
    }

    var context: ContextWindow? {
        guard let used = contextWindow?.totalInputTokens,
              let size = contextWindow?.contextWindowSize, size > 0 else { return nil }
        return ContextWindow(usedTokens: used, size: size)
    }

    var usage: UsageSnapshot? {
        guard let limits = rateLimits else { return nil }
        let snapshot = UsageSnapshot(
            fiveHour: limits.fiveHour?.window,
            sevenDay: limits.sevenDay?.window,
            sevenDayOpus: limits.sevenDayOpus?.window,
            sevenDaySonnet: limits.sevenDaySonnet?.window,
            updatedAt: Date()
        )
        return snapshot.isEmpty ? nil : snapshot
    }
}

extension StatusLinePayload.WindowPayload {
    var window: RateLimitWindow? {
        guard let usedPercentage else { return nil }
        return RateLimitWindow(usedPercentage: usedPercentage, resetsAt: resetsAt?.date)
    }
}

/// `resets_at` has been seen as epoch seconds, epoch milliseconds and ISO-8601,
/// so accept all three rather than betting on one.
struct ResetTimestamp: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            date = Self.fromEpoch(number)
        } else if let text = try? container.decode(String.self) {
            if let number = Double(text) {
                date = Self.fromEpoch(number)
            } else {
                date = ISO8601DateFormatter().date(from: text)
            }
        } else {
            date = nil
        }
    }

    /// Anything past the year ~2286 in seconds is really milliseconds.
    private static func fromEpoch(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }
}
