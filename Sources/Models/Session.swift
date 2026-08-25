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
    /// Terminal the session runs in, learned from hook request headers.
    var origin: TerminalOrigin?
    /// Path to the session's JSONL transcript, sent with every hook.
    var transcriptPath: String?
    /// How full the context window is, from the status line when it has
    /// reported and from the transcript otherwise.
    var contextWindow: ContextWindow?

    /// The status line reports the real window size; a transcript can only be
    /// used to infer it, so a size learned there is never overwritten.
    private var hasAuthoritativeWindowSize = false
    private var lastContextRefresh = Date.distantPast
    private var contextRefreshInFlight = false

    init(id: String, cwd: String? = nil) {
        self.id = id
        self.startTime = Date()
        self.lastEventTime = Date()
        self.cwd = cwd
    }

    func handleEvent(_ event: HookEvent) {
        lastEventTime = Date()

        // Every hook carries the session's current directory, and it can move
        // (cd, worktree switch, /add-dir). Track it on every event so the name
        // never goes stale.
        if let cwd = event.cwd, !cwd.isEmpty, cwd != self.cwd {
            self.cwd = cwd
        }
        if let path = event.transcriptPath, !path.isEmpty {
            transcriptPath = path
        }

        switch event.hookEventName {
        case "SessionStart", "CwdChanged":
            if event.hookEventName == "SessionStart" { state = .idle }
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
            if let toolName = event.toolName { lastToolName = toolName }
        case "PermissionDenied":
            state = .working
        case "Notification":
            // Claude Code notifies on "needs your permission" and "waiting for input"
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

    // MARK: - Context window

    /// Applies an authoritative reading from Claude Code's status line.
    func applyStatusLineContext(_ window: ContextWindow) {
        contextWindow = window
        hasAuthoritativeWindowSize = true
    }

    /// Re-reads the transcript, at most once every `minimumInterval` seconds.
    /// Events arrive in bursts and transcripts are large, so this coalesces.
    func refreshContextIfStale(minimumInterval: TimeInterval = 3, now: Date = Date()) {
        guard let path = transcriptPath,
              !contextRefreshInFlight,
              now.timeIntervalSince(lastContextRefresh) >= minimumInterval else { return }

        contextRefreshInFlight = true
        lastContextRefresh = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let reading = ContextUsageReader.read(transcriptPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.contextRefreshInFlight = false
                guard let reading else { return }
                self.applyTranscriptContext(reading)
            }
        }
    }

    func applyTranscriptContext(_ reading: ContextWindow) {
        guard hasAuthoritativeWindowSize, let known = contextWindow else {
            contextWindow = reading
            return
        }
        contextWindow = ContextWindow(usedTokens: reading.usedTokens, size: known.size)
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
