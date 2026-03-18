import Foundation

struct HookEvent: Decodable {
    let sessionId: String
    let hookEventName: String
    let cwd: String?
    let toolName: String?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case notificationType = "notification_type"
    }
}

enum SessionState: String {
    case idle
    case thinking
    case toolExecuting = "tool_executing"
    case waitingForUser = "waiting_for_user"
    case stale
}
