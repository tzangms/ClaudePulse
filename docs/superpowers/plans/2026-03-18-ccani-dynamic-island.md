# ccani Dynamic Island Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that displays Claude Code's real-time status as a floating Dynamic Island capsule.

**Architecture:** Embedded HTTP server receives Claude Code hook events, a session manager tracks state per session, and a SwiftUI + NSPanel UI renders a floating capsule with expand/collapse animation. An `NSApplicationDelegate` coordinator class owns all long-lived state (server, session manager, panel).

**Tech Stack:** Swift, SwiftUI, NSPanel, NWListener (Network framework), macOS 14+

**Spec:** `docs/superpowers/specs/2026-03-18-ccani-dynamic-island-design.md`

---

### Task 1: Project Scaffolding

**Files:**
- Create: `ccani/Package.swift`
- Create: `ccani/Sources/ccaniApp.swift`
- Create: `ccani/Sources/Info.plist`

- [ ] **Step 1: Create Swift Package project structure**

```bash
mkdir -p /Users/tzangms/projects/ccani/ccani/Sources/Models
mkdir -p /Users/tzangms/projects/ccani/ccani/Sources/Managers
mkdir -p /Users/tzangms/projects/ccani/ccani/Sources/Server
mkdir -p /Users/tzangms/projects/ccani/ccani/Sources/Views
mkdir -p /Users/tzangms/projects/ccani/ccani/Sources/Setup
```

- [ ] **Step 2: Write Package.swift**

Create `ccani/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ccani",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ccani",
            path: "Sources",
            resources: [.process("Info.plist")]
        )
    ]
)
```

- [ ] **Step 3: Write Info.plist**

Create `ccani/Sources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>ccani</string>
    <key>CFBundleIdentifier</key>
    <string>com.ccani.app</string>
    <key>CFBundleVersion</key>
    <string>0.1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
```

Note: `LSUIElement = true` hides the app from the Dock — it runs as a background utility with only the floating panel visible.

- [ ] **Step 4: Write minimal app entry point with NSApplicationDelegate**

Create `ccani/Sources/ccaniApp.swift`:

```swift
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: DynamicIslandPanel?
    var server: HookServer?
    let sessionManager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Will be wired up in Task 9
    }
}

@main
struct CcaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 5: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

Expected: Build succeeds with no errors.

- [ ] **Step 6: Initialize git repo and commit**

```bash
cd /Users/tzangms/projects/ccani && git init
echo ".build/\n.swiftpm/\n.DS_Store\n.superpowers/" > .gitignore
git add .gitignore ccani/
git commit -m "feat: scaffold ccani Swift package with Info.plist"
```

---

### Task 2: Hook Event Model

**Files:**
- Create: `ccani/Sources/Models/HookEvent.swift`

- [ ] **Step 1: Write HookEvent model**

Create `ccani/Sources/Models/HookEvent.swift`:

```swift
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
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Models/HookEvent.swift
git commit -m "feat: add HookEvent model and SessionState enum"
```

---

### Task 3: Session Model & State Machine

**Files:**
- Create: `ccani/Sources/Models/Session.swift`

- [ ] **Step 1: Write Session model with state machine**

Create `ccani/Sources/Models/Session.swift`:

```swift
import Foundation

@Observable
class Session: Identifiable {
    let id: String  // session_id from Claude Code
    let startTime: Date
    var state: SessionState = .idle
    var lastEventTime: Date
    var cwd: String?

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
            state = .thinking
        case "PreToolUse":
            state = .toolExecuting
        case "PostToolUse", "PostToolUseFailure":
            state = .thinking
        case "PermissionRequest":
            state = .waitingForUser
        case "Stop":
            state = .idle
        default:
            break
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
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Models/Session.swift
git commit -m "feat: add Session model with state machine"
```

---

### Task 4: Session Manager

**Files:**
- Create: `ccani/Sources/Managers/SessionManager.swift`

- [ ] **Step 1: Write SessionManager**

Create `ccani/Sources/Managers/SessionManager.swift`:

```swift
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
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Managers/
git commit -m "feat: add SessionManager with staleness handling"
```

---

### Task 5: Embedded HTTP Server

**Files:**
- Create: `ccani/Sources/Server/HookServer.swift`

- [ ] **Step 1: Write HTTP server with single-instance detection**

Create `ccani/Sources/Server/HookServer.swift`:

```swift
import Foundation
import Network

class HookServer {
    private var listener: NWListener?
    private let onEvent: (HookEvent) -> Void
    private(set) var port: UInt16 = 19280

    init(onEvent: @escaping (HookEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() throws {
        // Check if another ccani instance is already running
        if let existingPort = readExistingPortFile(), isPortResponding(existingPort) {
            throw ServerError.anotherInstanceRunning(port: existingPort)
        }

        for candidatePort in UInt16(19280)...UInt16(19289) {
            do {
                let nwPort = NWEndpoint.Port(rawValue: candidatePort)!
                let params = NWParameters.tcp
                let listener = try NWListener(using: params, on: nwPort)
                self.listener = listener
                self.port = candidatePort
                writePortFile()

                listener.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }
                listener.stateUpdateHandler = { state in
                    if case .failed(let err) = state {
                        print("Server failed: \(err)")
                    }
                }
                listener.start(queue: .global(qos: .userInitiated))
                print("ccani server listening on port \(candidatePort)")
                return
            } catch {
                continue
            }
        }
        throw ServerError.noAvailablePort
    }

    func stop() {
        listener?.cancel()
        removePortFile()
    }

    // MARK: - Single Instance Detection

    private func readExistingPortFile() -> UInt16? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccani/port")
        guard let content = try? String(contentsOf: file, encoding: .utf8),
              let port = UInt16(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return port
    }

    private func isPortResponding(_ port: UInt16) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var responding = false

        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                responding = true
                semaphore.signal()
            } else if case .failed = state {
                semaphore.signal()
            }
        }
        connection.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + 1.0)
        connection.cancel()
        return responding
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveData(from: connection, accumulated: Data())
    }

    private func receiveData(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buffer = accumulated
            if let data = data { buffer.append(data) }

            if isComplete || error != nil {
                self?.processRequest(buffer, connection: connection)
            } else {
                self?.receiveData(from: connection, accumulated: buffer)
            }
        }
    }

    private func processRequest(_ data: Data, connection: NWConnection) {
        let response: String
        if let bodyRange = data.range(of: Data("\r\n\r\n".utf8)) {
            let body = data[bodyRange.upperBound...]
            if let event = try? JSONDecoder().decode(HookEvent.self, from: body) {
                DispatchQueue.main.async { self.onEvent(event) }
                response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
            } else {
                response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
            }
        } else {
            response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
        }

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Port File

    private func writePortFile() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ccani")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("port")
        try? "\(port)".write(to: file, atomically: true, encoding: .utf8)
    }

    private func removePortFile() {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccani/port")
        try? FileManager.default.removeItem(at: file)
    }

    enum ServerError: Error, LocalizedError {
        case noAvailablePort
        case anotherInstanceRunning(port: UInt16)

        var errorDescription: String? {
            switch self {
            case .noAvailablePort:
                return "No available port in range 19280-19289"
            case .anotherInstanceRunning(let port):
                return "Another ccani instance is already running on port \(port)"
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Server/
git commit -m "feat: add embedded HTTP server with single-instance detection"
```

---

### Task 6: Dynamic Island Panel (NSPanel wrapper)

**Files:**
- Create: `ccani/Sources/Views/DynamicIslandPanel.swift`

- [ ] **Step 1: Write NSPanel wrapper**

Create `ccani/Sources/Views/DynamicIslandPanel.swift`:

```swift
import SwiftUI
import AppKit

class DynamicIslandPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        self.contentView = contentView
        positionAtTopCenter()
    }

    func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.maxY - frame.height - 8
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func resizeForExpanded(_ expanded: Bool) {
        let newHeight: CGFloat = expanded ? 240 : 36
        var newFrame = frame
        let oldHeight = newFrame.height
        newFrame.size.height = newHeight
        newFrame.origin.y -= (newHeight - oldHeight)
        setFrame(newFrame, display: true, animate: true)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Views/DynamicIslandPanel.swift
git commit -m "feat: add DynamicIslandPanel NSPanel wrapper"
```

---

### Task 7: Capsule View (Collapsed UI)

**Files:**
- Create: `ccani/Sources/Views/CapsuleView.swift`

- [ ] **Step 1: Write collapsed capsule view with vibrancy**

Create `ccani/Sources/Views/CapsuleView.swift`:

```swift
import SwiftUI

struct CapsuleView: View {
    let session: Session?
    let sessionCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .modifier(PulseAnimation(state: session?.state ?? .idle))

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            if session != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(session?.formattedTime ?? "00:00")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if sessionCount > 1 {
                HStack(spacing: 3) {
                    ForEach(0..<min(sessionCount - 1, 3), id: \.self) { _ in
                        Circle()
                            .fill(.white.opacity(0.4))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 200, height: 36)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var statusColor: Color {
        switch session?.state ?? .idle {
        case .idle: return .gray
        case .thinking: return .purple
        case .toolExecuting: return .blue
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var statusText: String {
        switch session?.state ?? .idle {
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .toolExecuting: return "Executing..."
        case .waitingForUser: return "Waiting"
        case .stale: return "Stale"
        }
    }
}

struct PulseAnimation: ViewModifier {
    let state: SessionState

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(pulseOpacity)
            .scaleEffect(pulseScale)
            .onAppear { phase = 1 }
            .onChange(of: state) { _, _ in phase = 0; phase = 1 }
            .animation(animation, value: phase)
    }

    private var pulseOpacity: Double {
        switch state {
        case .thinking: return phase == 1 ? 0.4 : 1.0
        case .toolExecuting: return phase == 1 ? 0.5 : 1.0
        case .waitingForUser: return phase == 1 ? 0.3 : 1.0
        default: return 1.0
        }
    }

    private var pulseScale: CGFloat {
        switch state {
        case .toolExecuting: return phase == 1 ? 1.3 : 1.0
        default: return 1.0
        }
    }

    private var animation: Animation? {
        switch state {
        case .thinking: return .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        case .toolExecuting: return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .waitingForUser: return .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        default: return nil
        }
    }
}
```

Note: Uses `.ultraThinMaterial` with forced `.dark` color scheme for the frosted glass vibrancy effect matching the spec.

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Views/CapsuleView.swift
git commit -m "feat: add CapsuleView with vibrancy and pulse animations"
```

---

### Task 8: Expanded View

**Files:**
- Create: `ccani/Sources/Views/ExpandedView.swift`

- [ ] **Step 1: Write expanded card view**

Create `ccani/Sources/Views/ExpandedView.swift`:

```swift
import SwiftUI

struct ExpandedView: View {
    let session: Session?
    let sessions: [Session]
    let onSelectSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if let session = session {
                HStack {
                    Text("Session")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(session.formattedTime)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }

                if let cwd = session.cwd {
                    Text(shortPath(cwd))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if sessions.count > 1 {
                Divider().background(.white.opacity(0.2))

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sessions) { s in
                            SessionRow(session: s, isActive: s.id == session?.id)
                                .onTapGesture { onSelectSession(s.id) }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
    }

    private var statusColor: Color {
        switch session?.state ?? .idle {
        case .idle: return .gray
        case .thinking: return .purple
        case .toolExecuting: return .blue
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var statusText: String {
        switch session?.state ?? .idle {
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .toolExecuting: return "Executing..."
        case .waitingForUser: return "Waiting for Input"
        case .stale: return "Stale"
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct SessionRow: View {
    let session: Session
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? .white : .white.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(session.cwd.map { ($0 as NSString).lastPathComponent } ?? String(session.id.prefix(8)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.6))
                .lineLimit(1)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(session.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Views/ExpandedView.swift
git commit -m "feat: add ExpandedView with session list"
```

---

### Task 9: Wire Everything Together in AppDelegate

**Files:**
- Modify: `ccani/Sources/ccaniApp.swift`

- [ ] **Step 1: Implement AppDelegate with panel, server, and click-outside collapse**

Replace `ccani/Sources/ccaniApp.swift`:

```swift
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: DynamicIslandPanel?
    var server: HookServer?
    let sessionManager = SessionManager()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        startServer()
        setupClickOutsideMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupPanel() {
        let contentView = DynamicIslandContent(
            sessionManager: sessionManager,
            onExpandChanged: { [weak self] expanded in
                self?.panel?.resizeForExpanded(expanded)
            }
        )
        let hostView = NSHostingView(rootView: contentView)
        hostView.frame = NSRect(x: 0, y: 0, width: 200, height: 36)

        let panel = DynamicIslandPanel(contentView: hostView)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func startServer() {
        let server = HookServer { [weak self] event in
            self?.sessionManager.handleEvent(event)
        }
        do {
            try server.start()
            self.server = server
        } catch HookServer.ServerError.anotherInstanceRunning {
            print("Another ccani instance is already running. Exiting.")
            NSApp.terminate(nil)
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            // Post notification that a click outside occurred
            NotificationCenter.default.post(name: .ccaniClickOutside, object: nil)
        }
    }
}

extension Notification.Name {
    static let ccaniClickOutside = Notification.Name("ccaniClickOutside")
}

@main
struct CcaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct DynamicIslandContent: View {
    let sessionManager: SessionManager
    let onExpandChanged: (Bool) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                ExpandedView(
                    session: sessionManager.activeSession,
                    sessions: sessionManager.sortedSessions,
                    onSelectSession: { id in
                        sessionManager.selectSession(id)
                    }
                )
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            } else {
                CapsuleView(
                    session: sessionManager.activeSession,
                    sessionCount: sessionManager.sessions.count
                )
                .transition(.scale(scale: 1.05, anchor: .top).combined(with: .opacity))
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            onExpandChanged(isExpanded)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ccaniClickOutside)) { _ in
            if isExpanded {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded = false
                }
                onExpandChanged(false)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 3: Test run the app**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift run &
sleep 2
```

Expected: App launches with no Dock icon. Capsule appears at top-center showing "Idle" with gray dot.

- [ ] **Step 4: Test with manual curl commands**

```bash
# Create a session
curl -sf -X POST http://localhost:19280/hook \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"test-1","hook_event_name":"SessionStart","cwd":"/tmp/test"}'

# Trigger thinking
curl -sf -X POST http://localhost:19280/hook \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"test-1","hook_event_name":"UserPromptSubmit"}'
```

Expected: Capsule shows "Thinking..." with purple breathing dot and timer counting.

- [ ] **Step 5: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/ccaniApp.swift
git commit -m "feat: wire up AppDelegate with panel, server, and click-outside collapse"
```

---

### Task 10: Hooks Auto-Configuration

**Files:**
- Create: `ccani/Sources/Setup/HooksConfigurator.swift`

- [ ] **Step 1: Write HooksConfigurator with user confirmation**

Create `ccani/Sources/Setup/HooksConfigurator.swift`:

```swift
import Foundation
import AppKit

struct HooksConfigurator {
    private let settingsPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    func needsSetup() -> Bool {
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return true
        }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard let hookList = entry["hooks"] as? [[String: Any]] else { continue }
                for hook in hookList {
                    if let url = hook["url"] as? String, url.contains("1928") { return false }
                    if let cmd = hook["command"] as? String, cmd.contains("ccani") { return false }
                }
            }
        }
        return true
    }

    func promptAndInstall(port: UInt16) {
        let alert = NSAlert()
        alert.messageText = "Configure Claude Code Hooks?"
        alert.informativeText = "ccani needs to add hooks to ~/.claude/settings.json to receive events from Claude Code. This will not overwrite your existing hooks."
        alert.addButton(withTitle: "Configure")
        alert.addButton(withTitle: "Skip")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            do {
                try install(port: port)
                print("Claude Code hooks configured for ccani on port \(port)")
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Failed to configure hooks"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }

    private func install(port: UInt16) throws {
        var json: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: settingsPath.path) {
            let data = try Data(contentsOf: settingsPath)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError.malformedSettings
            }
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let httpEvents = [
            "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "PermissionRequest", "Stop"
        ]
        let commandEvents = ["SessionStart", "SessionEnd"]

        for event in httpEvents {
            let entry: [String: Any] = [
                "matcher": "",
                "hooks": [["type": "http", "url": "http://localhost:\(port)/hook"]]
            ]
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.append(entry)
            hooks[event] = existing
        }

        let curlCmd = "curl -sf -X POST -H 'Content-Type: application/json' -d \"$(cat)\" http://localhost:$(cat ~/.ccani/port 2>/dev/null || echo \(port))/hook || true"
        for event in commandEvents {
            let entry: [String: Any] = [
                "matcher": "",
                "hooks": [["type": "command", "command": curlCmd]]
            ]
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.append(entry)
            hooks[event] = existing
        }

        json["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: settingsPath.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try data.write(to: settingsPath, options: .atomic)
    }

    enum ConfigError: Error, LocalizedError {
        case malformedSettings

        var errorDescription: String? {
            "~/.claude/settings.json contains malformed JSON. Please fix it manually and restart ccani."
        }
    }
}
```

- [ ] **Step 2: Wire configurator into AppDelegate**

Add to `AppDelegate.startServer()`, after `self.server = server`:

```swift
let configurator = HooksConfigurator()
if configurator.needsSetup() {
    configurator.promptAndInstall(port: server.port)
}
```

- [ ] **Step 3: Verify it builds**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build
```

- [ ] **Step 4: Commit**

```bash
cd /Users/tzangms/projects/ccani && git add ccani/Sources/Setup/ ccani/Sources/ccaniApp.swift
git commit -m "feat: add hooks auto-configuration with user confirmation dialog"
```

---

### Task 11: Final Integration Test

- [ ] **Step 1: Build release and launch**

```bash
cd /Users/tzangms/projects/ccani/ccani && swift build -c release && .build/release/ccani &
sleep 2
```

Expected: Capsule appears at top-center. If first run, a dialog asks to configure hooks.

- [ ] **Step 2: Simulate a full Claude Code session lifecycle**

```bash
PORT=$(cat ~/.ccani/port 2>/dev/null || echo 19280)

# Session start
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"SessionStart","cwd":"/Users/tzangms/projects/ccani"}' \
  http://localhost:$PORT/hook

sleep 2

# User prompt → thinking
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' \
  http://localhost:$PORT/hook

sleep 2

# Tool execution
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash"}' \
  http://localhost:$PORT/hook

sleep 2

# Tool done → back to thinking
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash"}' \
  http://localhost:$PORT/hook

sleep 1

# Permission request → waiting
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf"}}' \
  http://localhost:$PORT/hook

sleep 2

# Stop → idle
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"Stop"}' \
  http://localhost:$PORT/hook

# Second session
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s2","hook_event_name":"SessionStart","cwd":"/tmp/other-project"}' \
  http://localhost:$PORT/hook

sleep 1

# End first session
curl -sf -X POST -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","hook_event_name":"SessionEnd"}' \
  http://localhost:$PORT/hook
```

Expected:
- Capsule transitions: Idle → Thinking (purple) → Executing (blue) → Thinking (purple) → Waiting (orange blink) → Idle (gray)
- Timer counts up continuously
- Second session creates a dot indicator
- Click capsule → expands to show both sessions
- After s1 ends, only s2 remains
- Click outside → collapses

- [ ] **Step 3: Kill the app and verify cleanup**

```bash
kill %1
cat ~/.ccani/port  # Should fail — port file removed
```

- [ ] **Step 4: Final commit**

```bash
cd /Users/tzangms/projects/ccani && git add -A
git commit -m "feat: ccani v0.1 — Claude Code Dynamic Island for macOS"
```
