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

            // Defer hooks setup to avoid blocking app launch with modal dialog
            let port = server.port
            DispatchQueue.main.async {
                let configurator = HooksConfigurator()
                if configurator.needsSetup() {
                    configurator.promptAndInstall(port: port)
                }
            }
        } catch HookServer.ServerError.anotherInstanceRunning {
            print("Another ccani instance is already running. Exiting.")
            NSApp.terminate(nil)
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
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
