import Foundation

enum PermissionDecision {
    /// Allow this one call.
    case allow
    /// Allow and persist the rules Claude Code suggested ("don't ask again").
    case allowAlways
    case deny
    /// Return no decision so Claude Code shows its own prompt in the terminal.
    case deferToTerminal
}

/// The verbs shown on a prompt's buttons.
struct PermissionVocabulary: Equatable {
    var allow: String
    var deny: String
    var offersAllowAlways: Bool
    /// What the deny button means, for the tooltip.
    var denyHelp: String

    static let standard = PermissionVocabulary(
        allow: "Allow",
        deny: "Deny",
        offersAllowAlways: true,
        denyHelp: "Block this call"
    )

    static let plan = PermissionVocabulary(
        allow: "Accept",
        deny: "Revise",
        offersAllowAlways: false,
        denyHelp: "Send Claude back to planning"
    )

    static let question = PermissionVocabulary(
        allow: "Ask me",
        deny: "Skip",
        offersAllowAlways: false,
        denyHelp: "Skip the question"
    )

    static func forTool(_ toolName: String) -> PermissionVocabulary {
        switch toolName {
        case "ExitPlanMode", "exit_plan_mode": return .plan
        case "AskUserQuestion": return .question
        default: return .standard
        }
    }
}

/// A permission prompt Claude Code is blocked on while Pulse holds the hook
/// connection open. Answering it writes the decision back as the HTTP response.
@Observable
final class PendingPermission: Identifiable {
    let id: String
    let sessionId: String
    let toolName: String
    let toolInput: JSONValue?
    let suggestions: [JSONValue]
    let createdAt: Date
    let expiresAt: Date
    private let responder: (PermissionDecision) -> Void
    private var answered = false

    init(
        id: String,
        sessionId: String,
        toolName: String,
        toolInput: JSONValue?,
        suggestions: [JSONValue],
        timeout: TimeInterval,
        responder: @escaping (PermissionDecision) -> Void
    ) {
        self.id = id
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolInput = toolInput
        self.suggestions = suggestions
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(timeout)
        self.responder = responder
    }

    var canAllowAlways: Bool { !suggestions.isEmpty && vocabulary.offersAllowAlways }

    /// Wording for the buttons. "Allow / Deny" is right for a tool that is
    /// about to act, but wrong for the prompts Claude Code routes through the
    /// same permission machinery — approving a plan is accepting it, and
    /// declining sends Claude back to planning rather than blocking anything.
    var vocabulary: PermissionVocabulary { .forTool(toolName) }

    /// One-line summary of what the tool is about to do.
    var detail: String {
        guard let toolInput else { return "" }
        // Prefer the field that carries the meaning for the common tools.
        for key in ["command", "file_path", "path", "url", "pattern", "prompt"] {
            if let value = toolInput[key]?.displayText, !value.isEmpty {
                return value
            }
        }
        return toolInput.displayText
    }

    /// Everything the tool was asked to do, for when the one-line summary is
    /// not enough to decide on — a long command, a whole plan, a diff.
    var fullDetail: String {
        guard let toolInput, case .object(let fields) = toolInput else { return detail }
        return fields.sorted { $0.key < $1.key }
            .map { key, value in
                let text = value.displayText
                return text.contains("\n") ? "\(key):\n\(text)" : "\(key): \(text)"
            }
            .joined(separator: "\n")
    }

    /// True when the expanded detail says more than the summary line already does.
    var hasMoreDetail: Bool {
        let summary = detail
        let full = fullDetail
        return full != summary && !full.isEmpty
    }

    func respond(_ decision: PermissionDecision) {
        guard !answered else { return }
        answered = true
        responder(decision)
    }
}
