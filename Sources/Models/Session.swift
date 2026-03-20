import Foundation
import AppKit

@Observable
class Session: Identifiable {
    let id: String  // session_id from Claude Code
    let startTime: Date
    var state: SessionState = .idle
    var lastEventTime: Date
    var cwd: String?
    var lastToolName: String?
    var lastPrompt: String?

    init(id: String, cwd: String? = nil) {
        self.id = id
        self.startTime = Date()
        self.lastEventTime = Date()
        self.cwd = cwd
    }

    func handleEvent(_ event: HookEvent) {
        lastEventTime = Date()

        switch event.hookEventName {
        case "SessionStart":
            state = .idle
            if let cwd = event.cwd { self.cwd = cwd }
        case "UserPromptSubmit":
            state = .working
            if let prompt = event.prompt {
                lastPrompt = prompt
            }
        case "PreToolUse", "PostToolUse", "PostToolUseFailure":
            state = .working
            if let toolName = event.toolName {
                lastToolName = toolName
            }
        case "PermissionRequest":
            state = .waitingForUser
        case "Stop":
            let wasWorking = state == .working
            state = .idle
            if wasWorking && PanelSettings.shared.soundOnComplete {
                NSSound(named: .init(PanelSettings.shared.soundName))?.play()
            }
        default:
            break
        }
    }

    var projectName: String {
        if let cwd = cwd {
            return (cwd as NSString).lastPathComponent
        }
        return String(id.prefix(8))
    }

    var isActive: Bool {
        switch state {
        case .working, .waitingForUser:
            return true
        default:
            return false
        }
    }

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var formattedTime: String {
        let total = Int(elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
