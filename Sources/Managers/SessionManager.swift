import Foundation

@Observable
class SessionManager {
    var sessions: [String: Session] = [:]
    /// Account-wide rate limits, as last reported by the status line.
    var usage: UsageSnapshot? = UsageSnapshot.restore()
    var activeSessionId: String?
    /// Permission prompts Claude Code is currently blocked on, oldest first.
    var pendingPermissions: [PendingPermission] = []
    private var stalenessTimer: Timer?
    private var planUsageTimer: Timer?
    private let planUsageReader = PlanUsageReader()
    private var planUsageFileDate: Date?
    private var permissionTimers: [String: Timer] = [:]

    init() {
        refreshPlanUsage()
        startPlanUsageCheck()
        startStalenessCheck()
    }

    var activeSession: Session? {
        // A session blocked on a permission prompt outranks everything else
        if let waitingId = pendingPermissions.first?.sessionId, let waiting = sessions[waitingId] {
            return waiting
        }
        // Prefer the user-selected session, but auto-switch to a running one
        if let id = activeSessionId, let selected = sessions[id], selected.isActive {
            return selected
        }
        // Find any actively running session
        if let running = sessions.values.first(where: { $0.isActive }) {
            return running
        }
        // Fall back to user-selected or first
        if let id = activeSessionId, let selected = sessions[id] {
            return selected
        }
        return sessions.values.first
    }

    var activeSessionCount: Int {
        sessions.values.filter { $0.isActive }.count
    }

    var sortedSessions: [Session] {
        sessions.values.sorted { a, b in
            // Active sessions first, then by most recent event
            if a.isActive != b.isActive { return a.isActive }
            return a.lastEventTime > b.lastEventTime
        }
    }

    func pendingPermissions(for sessionId: String) -> [PendingPermission] {
        pendingPermissions.filter { $0.sessionId == sessionId }
    }

    // MARK: - Events

    /// Entry point for every hook request. `connection` must be answered
    /// exactly once; everything except a held permission prompt answers now.
    func handleEvent(_ event: HookEvent, connection: HookConnection) {
        if event.hookEventName == "PermissionRequest",
           PanelSettings.shared.permissionControl {
            handlePermissionRequest(event, connection: connection)
            return
        }
        connection.respondEmpty()
        handleEvent(event)
    }

    func handleEvent(_ event: HookEvent) {
        if event.hookEventName == "SessionEnd" {
            clearPermissions(for: event.sessionId, decision: .deferToTerminal)
            sessions.removeValue(forKey: event.sessionId)
            if activeSessionId == event.sessionId {
                activeSessionId = sessions.keys.first
            }
            return
        }

        let session: Session
        if let existing = sessions[event.sessionId] {
            session = existing
        } else {
            session = Session(id: event.sessionId, cwd: event.cwd)
            sessions[event.sessionId] = session
            if activeSessionId == nil {
                activeSessionId = event.sessionId
            }
        }
        if let origin = event.origin {
            session.origin = origin
        }
        session.handleEvent(event)
        session.refreshContextIfStale()

        // Claude Code moved on, so any prompt still on screen is obsolete.
        if ["PostToolUse", "PermissionDenied", "Stop"].contains(event.hookEventName) {
            clearPermissions(for: event.sessionId, decision: .deferToTerminal)
        }
    }

    private func handlePermissionRequest(_ event: HookEvent, connection: HookConnection) {
        handleEvent(event)

        let timeout = max(5, PanelSettings.shared.permissionTimeout)
        let id = event.toolUseId ?? UUID().uuidString
        let suggestions = event.permissionSuggestions ?? []

        let permission = PendingPermission(
            id: id,
            sessionId: event.sessionId,
            toolName: event.toolName ?? "tool",
            toolInput: event.toolInput,
            suggestions: suggestions,
            timeout: timeout
        ) { [weak self] decision in
            connection.respond(json: Self.hookOutput(for: decision, suggestions: suggestions))
            DispatchQueue.main.async { self?.removePermission(id: id) }
        }

        sessions[event.sessionId]?.state = .waitingForUser
        // The prompt offers to hand the decision back to the terminal, which
        // only makes sense for sessions that have one.
        sessions[event.sessionId]?.resolveClaudeDesktopIfNeeded()
        pendingPermissions.append(permission)

        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.pendingPermissions.first { $0.id == id }?.respond(.deferToTerminal)
        }
        permissionTimers[id] = timer

        NotificationCenter.default.post(name: .ccaniPermissionsChanged, object: nil)
    }

    /// Builds the `PermissionRequest` hook output Claude Code expects.
    static func hookOutput(for decision: PermissionDecision, suggestions: [JSONValue]) -> [String: Any] {
        var decisionBody: [String: Any]
        switch decision {
        case .deferToTerminal:
            return [:]
        case .allow:
            decisionBody = ["behavior": "allow"]
        case .allowAlways:
            decisionBody = ["behavior": "allow"]
            if !suggestions.isEmpty,
               let data = try? JSONEncoder().encode(suggestions),
               let updates = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                decisionBody["updatedPermissions"] = updates
            }
        case .deny:
            decisionBody = ["behavior": "deny", "message": "Denied from Pulse"]
        }
        return [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionBody
            ]
        ]
    }

    func respond(to permission: PendingPermission, decision: PermissionDecision) {
        permission.respond(decision)
        removePermission(id: permission.id)
        applyDecisionOptimistically(to: permission.sessionId, decision: decision)
    }

    /// Answering unblocks Claude Code immediately, but the next hook — the one
    /// that would move the row out of "waiting" — is a couple of seconds away.
    /// The outcome is already known here, so the row is updated now and the
    /// context re-read once Claude has had a moment to act on the answer.
    private func applyDecisionOptimistically(to sessionId: String, decision: PermissionDecision) {
        guard let session = sessions[sessionId] else { return }

        session.lastEventTime = Date()
        switch decision {
        case .allow, .allowAlways, .deny:
            // Claude carries on either way: it runs the tool, or it is told it
            // may not and reacts to that.
            session.state = .working
        case .deferToTerminal:
            // The prompt moved to the terminal — the user still owes an answer.
            session.state = .waitingForUser
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.postDecisionRefreshDelay) { [weak session] in
            session?.refreshContextIfStale(minimumInterval: 0)
        }
    }

    /// Long enough for Claude Code to have written its next transcript lines,
    /// short enough that the panel feels like it reacted to the click.
    static let postDecisionRefreshDelay: TimeInterval = 0.5

    private func removePermission(id: String) {
        permissionTimers.removeValue(forKey: id)?.invalidate()
        pendingPermissions.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .ccaniPermissionsChanged, object: nil)
    }

    private func clearPermissions(for sessionId: String, decision: PermissionDecision) {
        for permission in pendingPermissions where permission.sessionId == sessionId {
            permission.respond(decision)
            permissionTimers.removeValue(forKey: permission.id)?.invalidate()
        }
        pendingPermissions.removeAll { $0.sessionId == sessionId }
        NotificationCenter.default.post(name: .ccaniPermissionsChanged, object: nil)
    }

    /// Release every held hook so no session is left blocked when Pulse quits.
    func releaseAllPermissions() {
        for permission in pendingPermissions {
            permission.respond(.deferToTerminal)
        }
        permissionTimers.values.forEach { $0.invalidate() }
        permissionTimers.removeAll()
        pendingPermissions.removeAll()
    }

    // MARK: - Account usage

    /// Claude for Desktop samples the limits every few minutes, so checking
    /// once a minute is enough, and the file is only re-read when it changes.
    private func startPlanUsageCheck() {
        planUsageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshPlanUsage()
        }
    }

    func refreshPlanUsage(now: Date = Date()) {
        let modified = planUsageReader.modifiedAt()
        if let modified, modified == planUsageFileDate { return }
        planUsageFileDate = modified

        guard let snapshot = planUsageReader.read(now: now) else { return }
        adopt(snapshot)
    }

    /// The status line and the desktop app's history describe the same limits
    /// from different vantage points, so the more recent reading wins.
    private func adopt(_ snapshot: UsageSnapshot) {
        if let current = usage, current.updatedAt > snapshot.updatedAt { return }
        usage = snapshot
        snapshot.persist()
    }

    /// Claude Code renders its status line per session, so each payload updates
    /// that session's context reading and the shared rate limits.
    func handleStatusLine(_ payload: StatusLinePayload) {
        if let snapshot = payload.usage {
            adopt(snapshot)
        }
        if let sessionId = payload.sessionId,
           let context = payload.context,
           let session = sessions[sessionId] {
            session.applyStatusLineContext(context)
        }
    }

    func selectSession(_ id: String) {
        if sessions[id] != nil {
            activeSessionId = id
        }
    }

    private func startStalenessCheck() {
        stalenessTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkStaleness()
        }
    }

    private func checkStaleness() {
        guard !sessions.isEmpty else { return }
        let now = Date()
        for (id, session) in sessions {
            // A session blocked on a permission prompt is not stale, it is waiting on us.
            if pendingPermissions.contains(where: { $0.sessionId == id }) { continue }
            let elapsed = now.timeIntervalSince(session.lastEventTime)
            if elapsed > 1800 { // 30 min — remove
                sessions.removeValue(forKey: id)
                if activeSessionId == id {
                    activeSessionId = sessions.keys.first
                }
            } else if elapsed > 600 { // 10 min — mark stale
                session.state = .stale
            } else if session.isActive && elapsed > 30 { // 30 sec with no event — back to idle
                session.state = .idle
            }
        }
    }
}
