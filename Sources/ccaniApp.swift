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
        let server = HookServer { [weak self] event in
            self?.sessionManager.handleEvent(event)
        }
        do {
            try server.start()
            self.server = server

            // Defer hooks setup to avoid blocking app launch with modal dialog
            let port = server.port
            DispatchQueue.main.async {
                let configurator = HooksConfigurator()
                if configurator.needsSetup() {
                    configurator.promptAndInstall(port: port)
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
    }

    @objc private func openSettingsWindow() {
        settingsController.showSettings(updateChecker: updateChecker)
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

struct DynamicIslandContent: View {
    let sessionManager: SessionManager
    let settings = PanelSettings.shared

    @State private var isExpanded = false
    @State private var settingsHovered = false
    @State private var pinHovered = false

    private var shouldExpand: Bool {
        settings.pinExpanded || isExpanded
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
                if settings.pinExpanded { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded = hovering
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .ccaniClickOutside)) { _ in
            if !settings.pinExpanded {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    isExpanded = false
                }
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if expandsUpward {
            actionButtons
            detailSection
        } else {
            detailSection
            actionButtons
        }
    }

    private var detailSection: some View {
        ExpandedDetailView(
            session: sessionManager.activeSession,
            sessions: sessionManager.sortedSessions,
            onSelectSession: { id in
                sessionManager.selectSession(id)
            }
        )
        .padding(.top, expandsUpward ? 0 : 4)
    }

    private var actionButtons: some View {
        let s = settings.textSize.scale
        return HStack(spacing: 0) {
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
