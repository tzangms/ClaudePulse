import XCTest
@testable import ccpulse

final class PermissionTests: XCTestCase {

    private func decode(_ json: String) throws -> HookEvent {
        try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }

    func testDecodesPermissionRequestPayload() throws {
        let event = try decode("""
        {
          "session_id": "s1",
          "hook_event_name": "PermissionRequest",
          "cwd": "/repo",
          "tool_name": "Bash",
          "tool_use_id": "toolu_1",
          "tool_input": {"command": "rm -rf build", "description": "clean"},
          "permission_suggestions": [
            {"type": "addRules", "rules": [{"toolName": "Bash", "ruleContent": "rm:*"}],
             "behavior": "allow", "destination": "session"}
          ]
        }
        """)

        XCTAssertEqual(event.toolUseId, "toolu_1")
        XCTAssertEqual(event.toolInput?["command"]?.stringValue, "rm -rf build")
        XCTAssertEqual(event.permissionSuggestions?.count, 1)
    }

    func testDetailPrefersCommand() throws {
        let event = try decode("""
        {"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "tool_input":{"description":"clean","command":"make test"}}
        """)
        let permission = PendingPermission(
            id: "1", sessionId: "s", toolName: "Bash",
            toolInput: event.toolInput, suggestions: [], timeout: 60, responder: { _ in }
        )
        XCTAssertEqual(permission.detail, "make test")
    }

    func testAllowAlwaysEchoesSuggestions() throws {
        let event = try decode("""
        {"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "permission_suggestions":[
           {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"ls:*"}],
            "behavior":"allow","destination":"session"}]}
        """)
        let output = SessionManager.hookOutput(for: .allowAlways, suggestions: event.permissionSuggestions ?? [])

        let specific = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(specific["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")

        let updates = try XCTUnwrap(decision["updatedPermissions"] as? [[String: Any]])
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0]["type"] as? String, "addRules")
        XCTAssertEqual(updates[0]["destination"] as? String, "session")
        let rules = try XCTUnwrap(updates[0]["rules"] as? [[String: Any]])
        XCTAssertEqual(rules[0]["ruleContent"] as? String, "ls:*")
    }

    func testPlainAllowCarriesNoPermissionUpdates() {
        let output = SessionManager.hookOutput(for: .allow, suggestions: [.string("ignored")])
        let decision = (output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "allow")
        XCTAssertNil(decision?["updatedPermissions"])
    }

    func testDenyCarriesMessage() {
        let output = SessionManager.hookOutput(for: .deny, suggestions: [])
        let decision = (output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "deny")
        XCTAssertNotNil(decision?["message"])
    }

    /// Deferring must produce an empty object, which Claude Code reads as
    /// "no hook decision" and falls back to its own prompt.
    func testDeferProducesNoDecision() {
        XCTAssertTrue(SessionManager.hookOutput(for: .deferToTerminal, suggestions: []).isEmpty)
    }

    func testRespondIsIdempotent() {
        var calls = 0
        let permission = PendingPermission(
            id: "1", sessionId: "s", toolName: "Bash",
            toolInput: nil, suggestions: [], timeout: 60,
            responder: { _ in calls += 1 }
        )
        permission.respond(.allow)
        permission.respond(.deny)
        XCTAssertEqual(calls, 1)
    }

    func testAllowAlwaysOnlyOfferedWithSuggestions() {
        let without = PendingPermission(id: "1", sessionId: "s", toolName: "Bash",
                                        toolInput: nil, suggestions: [], timeout: 60, responder: { _ in })
        let with = PendingPermission(id: "2", sessionId: "s", toolName: "Bash",
                                     toolInput: nil, suggestions: [.string("x")], timeout: 60, responder: { _ in })
        XCTAssertFalse(without.canAllowAlways)
        XCTAssertTrue(with.canAllowAlways)
    }

    // MARK: - Hook definitions

    func testHookDefinitionIsHTTPWithEnvHeaders() throws {
        let hook = HooksConfigurator.hookDefinition(port: 19280, event: "SessionStart")
        XCTAssertEqual(hook["type"] as? String, "http")
        XCTAssertEqual(hook["url"] as? String, "http://127.0.0.1:19280/hook")

        let headers = try XCTUnwrap(hook["headers"] as? [String: String])
        XCTAssertEqual(headers["X-Pulse-Hook"], "1")
        XCTAssertEqual(headers["X-Pulse-Term-Program"], "$TERM_PROGRAM")

        // Interpolation only happens for variables listed here.
        let allowed = try XCTUnwrap(hook["allowedEnvVars"] as? [String])
        XCTAssertTrue(allowed.contains("TERM_PROGRAM"))
        XCTAssertTrue(allowed.contains("ITERM_SESSION_ID"))
    }

    func testPermissionTimeoutOnlyAppliesWhenControlEnabled() {
        let settings = PanelSettings.shared
        let originalControl = settings.permissionControl
        let originalTimeout = settings.permissionTimeout
        defer {
            settings.permissionControl = originalControl
            settings.permissionTimeout = originalTimeout
        }

        settings.permissionControl = false
        XCTAssertEqual(HooksConfigurator.timeout(for: "PermissionRequest"), 3)

        settings.permissionControl = true
        settings.permissionTimeout = 120
        XCTAssertEqual(HooksConfigurator.timeout(for: "PermissionRequest"), 130)
        // Non-blocking events stay short so a wedged Pulse never stalls a session.
        XCTAssertEqual(HooksConfigurator.timeout(for: "PreToolUse"), 3)
    }
}

final class PermissionRoutingTests: XCTestCase {
    private var socketPair: [Int32] = []

    /// A HookConnection needs a real fd; a socketpair gives us one we can read
    /// the response back from.
    private func makeConnection() -> (HookConnection, Int32) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        socketPair.append(fds[0])
        return (HookConnection(sock: fds[1]), fds[0])
    }

    private func readResponse(_ fd: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = read(fd, &buffer, 8192)
        guard n > 0 else { return "" }
        return String(decoding: buffer[0..<n], as: UTF8.self)
    }

    override func tearDown() {
        socketPair.forEach { close($0) }
        socketPair = []
        super.tearDown()
    }

    private func event(_ name: String, session: String = "s1", tool: String? = nil) -> HookEvent {
        var json: [String: Any] = ["session_id": session, "hook_event_name": name, "cwd": "/repo"]
        if let tool { json["tool_name"] = tool }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(HookEvent.self, from: data)
    }

    func testNonPermissionEventAnswersImmediately() {
        let manager = SessionManager()
        let (connection, readFD) = makeConnection()

        manager.handleEvent(event("UserPromptSubmit"), connection: connection)

        XCTAssertTrue(readResponse(readFD).hasSuffix("{}"))
        XCTAssertEqual(manager.sessions["s1"]?.state, .working)
        XCTAssertTrue(manager.pendingPermissions.isEmpty)
    }

    /// With the feature off, a permission request must not be held.
    func testPermissionRequestPassesThroughWhenControlDisabled() {
        let settings = PanelSettings.shared
        let original = settings.permissionControl
        defer { settings.permissionControl = original }
        settings.permissionControl = false

        let manager = SessionManager()
        let (connection, readFD) = makeConnection()
        manager.handleEvent(event("PermissionRequest", tool: "Bash"), connection: connection)

        XCTAssertTrue(readResponse(readFD).hasSuffix("{}"))
        XCTAssertTrue(manager.pendingPermissions.isEmpty)
    }

    func testPermissionRequestIsHeldAndAnswered() {
        let settings = PanelSettings.shared
        let original = settings.permissionControl
        defer { settings.permissionControl = original }
        settings.permissionControl = true

        let manager = SessionManager()
        let (connection, readFD) = makeConnection()
        manager.handleEvent(event("PermissionRequest", tool: "Bash"), connection: connection)

        XCTAssertEqual(manager.pendingPermissions.count, 1)
        XCTAssertEqual(manager.sessions["s1"]?.state, .waitingForUser)
        // The session with a prompt outranks selection when picking the capsule subject.
        XCTAssertEqual(manager.activeSession?.id, "s1")

        let permission = try! XCTUnwrap(manager.pendingPermissions.first)
        manager.respond(to: permission, decision: .deny)

        let response = readResponse(readFD)
        XCTAssertTrue(response.contains("PermissionRequest"), response)
        XCTAssertTrue(response.contains("deny"), response)
        XCTAssertTrue(manager.pendingPermissions.isEmpty)
    }

    /// If Claude Code moves on by itself, a stale prompt must release its hook.
    func testPostToolUseClearsPendingPermission() {
        let settings = PanelSettings.shared
        let original = settings.permissionControl
        defer { settings.permissionControl = original }
        settings.permissionControl = true

        let manager = SessionManager()
        let (connection, readFD) = makeConnection()
        manager.handleEvent(event("PermissionRequest", tool: "Bash"), connection: connection)
        XCTAssertEqual(manager.pendingPermissions.count, 1)

        let (other, _) = makeConnection()
        manager.handleEvent(event("PostToolUse", tool: "Bash"), connection: other)

        XCTAssertTrue(manager.pendingPermissions.isEmpty)
        XCTAssertTrue(readResponse(readFD).hasSuffix("{}"))
    }

    func testReleaseAllPermissionsUnblocksEveryone() {
        let settings = PanelSettings.shared
        let original = settings.permissionControl
        defer { settings.permissionControl = original }
        settings.permissionControl = true

        let manager = SessionManager()
        let (first, firstFD) = makeConnection()
        let (second, secondFD) = makeConnection()
        manager.handleEvent(event("PermissionRequest", session: "a", tool: "Bash"), connection: first)
        manager.handleEvent(event("PermissionRequest", session: "b", tool: "Write"), connection: second)
        XCTAssertEqual(manager.pendingPermissions.count, 2)

        manager.releaseAllPermissions()

        XCTAssertTrue(manager.pendingPermissions.isEmpty)
        XCTAssertTrue(readResponse(firstFD).hasSuffix("{}"))
        XCTAssertTrue(readResponse(secondFD).hasSuffix("{}"))
    }
}

final class PermissionDecisionFeedbackTests: XCTestCase {

    private func manager(withSession id: String) -> SessionManager {
        let manager = SessionManager()
        let session = Session(id: id, cwd: "/tmp")
        session.state = .waitingForUser
        manager.sessions[id] = session
        return manager
    }

    private func permission(sessionId: String, tool: String = "Bash") -> PendingPermission {
        PendingPermission(
            id: UUID().uuidString, sessionId: sessionId, toolName: tool,
            toolInput: nil, suggestions: [], timeout: 60, responder: { _ in }
        )
    }

    /// The row must stop saying "waiting" the moment the user answers, rather
    /// than when the next hook happens to arrive seconds later.
    func testAllowingMovesTheSessionBackToWorkingImmediately() {
        let manager = manager(withSession: "s1")
        manager.respond(to: permission(sessionId: "s1"), decision: .allow)

        XCTAssertEqual(manager.sessions["s1"]?.state, .working)
    }

    func testDenyingAlsoResumesTheSession() {
        let manager = manager(withSession: "s1")
        manager.respond(to: permission(sessionId: "s1"), decision: .deny)

        XCTAssertEqual(manager.sessions["s1"]?.state, .working)
    }

    /// Handing the prompt to the terminal leaves the user still owing an
    /// answer, so the session is genuinely still waiting.
    func testDeferringKeepsTheSessionWaiting() {
        let manager = manager(withSession: "s1")
        manager.respond(to: permission(sessionId: "s1"), decision: .deferToTerminal)

        XCTAssertEqual(manager.sessions["s1"]?.state, .waitingForUser)
    }

    /// A session that just answered has not gone quiet, and must not be aged
    /// out by the staleness sweep.
    func testAnsweringCountsAsActivity() {
        let manager = manager(withSession: "s1")
        manager.sessions["s1"]?.lastEventTime = Date().addingTimeInterval(-3600)

        manager.respond(to: permission(sessionId: "s1"), decision: .allow)

        let elapsed = Date().timeIntervalSince(try! XCTUnwrap(manager.sessions["s1"]?.lastEventTime))
        XCTAssertLessThan(elapsed, 1)
    }

    func testAnsweringForAnUnknownSessionIsHarmless() {
        let manager = manager(withSession: "s1")
        manager.respond(to: permission(sessionId: "gone"), decision: .allow)

        XCTAssertEqual(manager.sessions["s1"]?.state, .waitingForUser)
    }
}
