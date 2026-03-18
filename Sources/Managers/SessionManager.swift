import Foundation

@Observable
class SessionManager {
    var sessions: [String: Session] = [:]
    var activeSessionId: String?
    private var stalenessTimer: Timer?

    init() {
        startStalenessCheck()
    }

    var activeSession: Session? {
        guard let id = activeSessionId else { return sessions.values.first }
        return sessions[id]
    }

    var sortedSessions: [Session] {
        sessions.values.sorted { $0.startTime < $1.startTime }
    }

    func handleEvent(_ event: HookEvent) {
        if event.hookEventName == "SessionEnd" {
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
        session.handleEvent(event)
    }

    func selectSession(_ id: String) {
        if sessions[id] != nil {
            activeSessionId = id
        }
    }

    private func startStalenessCheck() {
        stalenessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkStaleness()
        }
    }

    private func checkStaleness() {
        let now = Date()
        for (id, session) in sessions {
            let elapsed = now.timeIntervalSince(session.lastEventTime)
            if elapsed > 1800 { // 30 min — remove
                sessions.removeValue(forKey: id)
                if activeSessionId == id {
                    activeSessionId = sessions.keys.first
                }
            } else if elapsed > 600 { // 10 min — mark stale
                session.state = .stale
            }
        }
    }
}
