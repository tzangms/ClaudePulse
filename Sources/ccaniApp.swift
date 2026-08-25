import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: DynamicIslandPanel?
    var server: HookServer?
    let sessionManager = SessionManager()
    let updateChecker = UpdateChecker()
    private var clickMonitor: Any?
    private var statusItem: NSStatusItem?
    private let settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Pulse] App launched")
        NSApp.setActivationPolicy(PanelSettings.shared.showDockIcon ? .regular : .accessory)
        setupPanel()
        print("[Pulse] Panel set up")
        startServer()
        print("[Pulse] Server started")
        setupClickOutsideMonitor()
        setupStatusItem()
        updateChecker.startPeriodicCheck()
        print("[Pulse] Ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager.releaseAllPermissions()
        server?.stop()
        updateChecker.stop()
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupPanel() {
        let contentView = DynamicIslandContent(sessionManager: sessionManager)
        let hostView = SizeTrackingHostingView(rootView: contentView)
        hostView.sizingOptions = [.intrinsicContentSize]

        let panel = DynamicIslandPanel(contentView: hostView)
        hostView.onSizeChange = { [weak panel] size in
            panel?.updateFrameForContentSize(size)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func startServer() {
        let server = HookServer(
            onEvent: { [weak self] event, connection in
                guard let self else {
                    connection.respondEmpty()
                    return
                }
                self.sessionManager.handleEvent(event, connection: connection)
            },
            onStatusLine: { [weak self] payload in
                self?.sessionManager.handleStatusLine(payload)
            }
        )
        do {
            try server.start()
            self.server = server

            // Defer hooks setup to avoid blocking app launch with modal dialog
            let port = server.port
            // `-disableHookSetup YES` keeps a development build from touching
            // ~/.claude/settings.json while a released Pulse owns it.
            guard !UserDefaults.standard.bool(forKey: "disableHookSetup") else { return }

            DispatchQueue.main.async {
                let configurator = HooksConfigurator()
                if configurator.needsSetup() {
                    configurator.promptAndInstall(port: port)
                }

                // Only kept up to date if the user has already opted in from
                // Settings. Pulse does not ask for the status line on launch:
                // account usage normally comes from Claude for Desktop's own
                // records, and taking the slot would break whatever status line
                // the user already has for no gain.
                let statusLine = StatusLineConfigurator()
                if statusLine.needsScriptRefresh(port: port) {
                    try? statusLine.refreshScript(port: port)
                } else {
                    // Port or permission settings may have changed since install.
                    configurator.syncIfNeeded(port: port)
                }
            }
        } catch HookServer.ServerError.anotherInstanceRunning {
            print("Another Pulse instance is already running. Exiting.")
            NSApp.terminate(nil)
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Pulse")
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(title: "Show/Hide Panel", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Pin expanded
        let pinItem = NSMenuItem(title: "Keep Expanded", action: #selector(togglePinExpanded(_:)), keyEquivalent: "")
        pinItem.target = self
        pinItem.tag = 100
        menu.addItem(pinItem)

        menu.addItem(NSMenuItem.separator())

        // Position submenu
        let posMenu = NSMenu()
        for pos in PanelPosition.allCases {
            let item = NSMenuItem(title: pos.displayName, action: #selector(changePosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pos.rawValue
            posMenu.addItem(item)
        }
        let posItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        posItem.submenu = posMenu
        menu.addItem(posItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = 200
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Pulse", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem

        // Listen for open-settings notification from panel buttons
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsWindow), name: .ccaniOpenSettings, object: nil)
        // Listen for reposition notification from settings view
        NotificationCenter.default.addObserver(self, selector: #selector(repositionPanel), name: .ccaniRepositionPanel, object: nil)
        // Fullscreen / level changes from settings
        NotificationCenter.default.addObserver(self, selector: #selector(applyPanelBehavior), name: .ccaniPanelBehaviorChanged, object: nil)
        // Permission prompts raise the panel above fullscreen apps while they last
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged), name: .ccaniPermissionsChanged, object: nil)
        // Hook config depends on settings (permission timeout, control on/off)
        NotificationCenter.default.addObserver(self, selector: #selector(syncHooks), name: .ccaniHooksNeedSync, object: nil)
    }

    @objc private func openSettingsWindow() {
        settingsController.showSettings(updateChecker: updateChecker)
    }

    @objc private func applyPanelBehavior() {
        panel?.applyWindowBehavior()
    }

    @objc private func permissionsChanged() {
        let waiting = !sessionManager.pendingPermissions.isEmpty
        panel?.isUrgent = waiting
        if waiting {
            panel?.orderFrontRegardless()
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    @objc private func syncHooks() {
        guard !UserDefaults.standard.bool(forKey: "disableHookSetup") else { return }
        guard let port = server?.port else { return }
        HooksConfigurator().syncIfNeeded(port: port)
    }

    @objc private func repositionPanel() {
        panel?.repositionForCurrentSettings()
    }

    @objc private func checkForUpdates() {
        updateChecker.checkForUpdates()
        if updateChecker.updateAvailable {
            updateChecker.openDownloadPage()
        }
    }

    @objc private func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func togglePinExpanded(_ sender: NSMenuItem) {
        PanelSettings.shared.pinExpanded.toggle()
    }

    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let position = PanelPosition(rawValue: rawValue) else { return }
        PanelSettings.shared.position = position
        panel?.repositionForCurrentSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Update pin checkmark
        if let pinItem = menu.item(withTag: 100) {
            pinItem.state = PanelSettings.shared.pinExpanded ? .on : .off
        }
        // Update position checkmarks in submenu
        if let posItem = menu.item(withTitle: "Position"),
           let posMenu = posItem.submenu {
            let current = PanelSettings.shared.position.rawValue
            for item in posMenu.items {
                item.state = (item.representedObject as? String) == current ? .on : .off
            }
        }
        // Update check-for-updates item
        if let updateItem = menu.item(withTag: 200) {
            if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                updateItem.title = "Update Available (v\(version))..."
            } else {
                updateItem.title = "Check for Updates..."
            }
        }
    }
}

extension AppDelegate {
    func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            NotificationCenter.default.post(name: .ccaniClickOutside, object: nil)
        }
    }
}

extension Notification.Name {
    static let ccaniClickOutside = Notification.Name("ccaniClickOutside")
    static let ccaniOpenSettings = Notification.Name("ccaniOpenSettings")
    static let ccaniRepositionPanel = Notification.Name("ccaniRepositionPanel")
    static let ccaniPanelBehaviorChanged = Notification.Name("ccaniPanelBehaviorChanged")
    static let ccaniPermissionsChanged = Notification.Name("ccaniPermissionsChanged")
    static let ccaniPermissionRequested = Notification.Name("ccaniPermissionRequested")
    static let ccaniHooksNeedSync = Notification.Name("ccaniHooksNeedSync")
}

@main
struct CcpulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private struct PanelVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var panelVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

struct DynamicIslandContent: View {
    let sessionManager: SessionManager
    let settings = PanelSettings.shared

    /// Expansion is driven by the capsule alone. The expanded body can only
    /// keep the panel open, never open it — otherwise the panel growing under
    /// a departing cursor re-triggers its own hover.
    @State private var capsuleHovered = false
    @State private var isExpanded = false
    @State private var hoverIntent: DispatchWorkItem?
    @State private var collapseIntent: DispatchWorkItem?
    @State private var settingsHovered = false
    @State private var pinHovered = false
    @State private var isPanelVisible = true

    /// Delay before a hover counts, so sweeping past the capsule does nothing.
    private let hoverIntentDelay: TimeInterval = 0.1
    private let expandAnimationDuration: TimeInterval = 0.35
    /// The panel grows under the cursor as it opens, so a moment of "not
    /// hovering" mid-animation is normal — collapsing needs to wait long enough
    /// for the cursor to be caught by the content moving towards it.
    private let collapseGrace: TimeInterval = 0.25

    private var permissions: [PendingPermission] {
        sessionManager.pendingPermissions
    }

    private var shouldExpand: Bool {
        settings.pinExpanded || isExpanded || !permissions.isEmpty
    }

    private var cornerRadius: CGFloat {
        shouldExpand ? 20 : 18
    }

    private var expandsUpward: Bool {
        settings.position == .bottomLeft || settings.position == .bottomRight
    }

    var body: some View {
        VStack(spacing: 0) {
            // For bottom positions: Spacer pushes content to bottom
            // within the fixed-height panel. Spacer doesn't intercept clicks.
            if expandsUpward {
                Spacer(minLength: 0)
            }

            // --- Visible content (hover target) ---
            VStack(spacing: 0) {
                if shouldExpand && expandsUpward {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }

                CapsuleView(
                    session: sessionManager.activeSession,
                    sessionCount: sessionManager.sessions.count,
                    activeCount: sessionManager.activeSessionCount
                )
                .onHover { hovering in
                    capsuleHovered = hovering
                    hovering ? scheduleExpand() : capsuleExited()
                }

                if shouldExpand && !expandsUpward {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .fixedSize()
            .padding(.bottom, shouldExpand && !expandsUpward ? 4 : 0)
            .padding(.top, shouldExpand && expandsUpward ? 4 : 0)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering in
                // Entering the panel never expands — only the capsule does that
                // — but staying inside it keeps it open.
                if hovering {
                    cancelCollapse()
                } else if !capsuleHovered {
                    scheduleCollapse()
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.panelVisible, isPanelVisible)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? DynamicIslandPanel else { return }
            isPanelVisible = window.occlusionState.contains(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ccaniClickOutside)) { _ in
            if !settings.pinExpanded {
                collapse()
            }
        }
    }

    // MARK: - Hover state machine

    private func scheduleExpand() {
        hoverIntent?.cancel()
        cancelCollapse()
        guard !isExpanded else { return }
        let work = DispatchWorkItem {
            // Still on the capsule after the delay, so this is intent rather
            // than a cursor passing through.
            guard capsuleHovered else { return }
            withAnimation(.spring(response: expandAnimationDuration, dampingFraction: 0.8)) {
                isExpanded = true
            }
        }
        hoverIntent = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverIntentDelay, execute: work)
    }

    /// The cursor left the capsule. That is the normal way into the session
    /// list, so it only cancels an expand that has not happened yet — whether
    /// the cursor actually left the panel is the outer hover's business.
    private func capsuleExited() {
        hoverIntent?.cancel()
        hoverIntent = nil
    }

    /// Collapses after a grace period, so a hover that returns — because the
    /// panel grew under the cursor, or the cursor crossed a seam between rows —
    /// keeps it open.
    private func scheduleCollapse() {
        guard isExpanded, collapseIntent == nil else { return }
        let work = DispatchWorkItem { collapse() }
        collapseIntent = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseGrace, execute: work)
    }

    private func cancelCollapse() {
        collapseIntent?.cancel()
        collapseIntent = nil
    }

    private func collapse() {
        hoverIntent?.cancel()
        hoverIntent = nil
        cancelCollapse()
        guard isExpanded else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isExpanded = false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var expandedContent: some View {
        if expandsUpward {
            actionButtons
            detailSection
            permissionSection
        } else {
            permissionSection
            detailSection
            actionButtons
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !permissions.isEmpty {
            PermissionListView(
                permissions: permissions,
                sessionName: { sessionManager.sessions[$0]?.projectName ?? "session" },
                onDecision: { permission, decision in
                    sessionManager.respond(to: permission, decision: decision)
                },
                onFocusSession: { sessionId in
                    sessionManager.selectSession(sessionId)
                    if let session = sessionManager.sessions[sessionId] {
                        SessionOpener.reveal(session)
                    }
                }
            )
        }
    }

    private var detailSection: some View {
        ExpandedDetailView(
            session: sessionManager.activeSession,
            sessions: sessionManager.sortedSessions,
            onSelectSession: { id in
                sessionManager.selectSession(id)
            },
            onOpenSession: { session, forceClaudeDesktop in
                SessionOpener.reveal(session, forceClaudeDesktop: forceClaudeDesktop)
            }
        )
        .padding(.top, expandsUpward ? 0 : 4)
    }

    private var actionButtons: some View {
        let s = settings.textSize.scale
        return HStack(spacing: 0) {
            if let usage = sessionManager.usage {
                GlobalUsageView(usage: usage)
                    .padding(.leading, 4)
            }
            Spacer()

            Button {
                NotificationCenter.default.post(name: .ccaniOpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(settingsHovered ? 0.8 : 0.35))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.15)) { settingsHovered = h }
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    settings.pinExpanded.toggle()
                }
            } label: {
                Image(systemName: settings.pinExpanded ? "pin.fill" : "pin")
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(
                        settings.pinExpanded
                            ? settings.accentColor
                            : .white.opacity(pinHovered ? 0.8 : 0.35)
                    )
                    .rotationEffect(.degrees(settings.pinExpanded ? 0 : 45))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.15)) { pinHovered = h }
            }
        }
        .padding(.horizontal, 10)
        .padding(expandsUpward ? .top : .bottom, 2)
    }
}
