import Foundation

/// Where a session is running, derived from headers the HTTP hook sends along
/// with each event (`$TERM_PROGRAM` and friends, interpolated by Claude Code).
struct TerminalOrigin: Equatable {
    var termProgram: String?
    var termSessionId: String?
    var itermSessionId: String?
    var weztermPane: String?
    var kittyWindowId: String?

    var isEmpty: Bool {
        termProgram == nil && termSessionId == nil && itermSessionId == nil
            && weztermPane == nil && kittyWindowId == nil
    }

    init(headers: [String: String]) {
        func value(_ name: String) -> String? {
            guard let raw = headers[name.lowercased()] else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        termProgram = value("x-pulse-term-program")
        termSessionId = value("x-pulse-term-session")
        itermSessionId = value("x-pulse-iterm-session")
        weztermPane = value("x-pulse-wezterm-pane")
        kittyWindowId = value("x-pulse-kitty-window")
    }
}

struct HookEvent: Decodable {
    let sessionId: String
    let hookEventName: String
    let cwd: String?
    let toolName: String?
    let notificationType: String?
    let prompt: String?
    let toolInput: JSONValue?
    let toolUseId: String?
    let permissionSuggestions: [JSONValue]?
    let transcriptPath: String?
    let permissionMode: String?
    let message: String?
    let reason: String?

    /// Filled in by `HookServer` from request headers, not from the JSON body.
    var origin: TerminalOrigin?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case notificationType = "notification_type"
        case prompt
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case permissionSuggestions = "permission_suggestions"
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case message
        case reason
    }
}

enum SessionState: String {
    case idle
    case working
    case waitingForUser = "waiting_for_user"
    case stale
}
