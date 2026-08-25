import AppKit
import Foundation

/// Brings the terminal (or editor) that owns a session to the front.
///
/// The hook sends `$TERM_PROGRAM` and the terminal's own session identifier as
/// request headers, which is enough to focus the exact tab in iTerm2, the exact
/// pane in WezTerm/kitty, or at least the right application everywhere else.
enum SessionOpener {

    /// - Parameter forceClaudeDesktop: set by an Option-click, which always
    ///   opens the session in Claude for Desktop regardless of the setting.
    static func reveal(_ session: Session, forceClaudeDesktop: Bool = false) {
        let origin = session.origin
        let cwd = session.cwd
        let sessionId = session.id
        let target = forceClaudeDesktop ? .claudeDesktop : PanelSettings.shared.revealTarget

        DispatchQueue.global(qos: .userInitiated).async {
            switch target {
            case .auto:
                // A known terminal is the session's real home. Only sessions
                // Pulse cannot place that way go to Claude for Desktop.
                if let origin, focus(origin: origin, cwd: cwd) { return }
                if openInClaudeDesktop(sessionId: sessionId) { return }
                revealWithFallback(cwd: cwd, target: .terminal)

            case .claudeDesktop:
                if openInClaudeDesktop(sessionId: sessionId) { return }
                _ = activate(bundleId: RevealTarget.claudeDesktop.bundleIdentifier!)

            default:
                revealWithFallback(cwd: cwd, target: target)
            }
        }
    }

    // MARK: - Claude for Desktop

    /// Focuses the desktop session that is running this Claude Code session.
    ///
    /// `claude://claude.ai/epitaxy/<desktop-id>` navigates the app straight to
    /// one of its own sessions. The obvious-looking alternative,
    /// `claude://resume?session=<cli-id>`, is an *import* link: it copies the
    /// transcript into a brand new session unless the app already holds one
    /// named `local_<cli-id>`, which is true of almost none of them. So Pulse
    /// resolves the live desktop session first and navigates to it by name.
    static func openInClaudeDesktop(sessionId: String) -> Bool {
        guard claudeDesktopIsInstalled else { return false }
        guard let desktopId = ClaudeDesktopSessions.liveTwin(of: sessionId) else { return false }
        guard let url = URL(string: "claude://claude.ai/epitaxy/\(desktopId)") else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    private static var claudeDesktopIsInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
    }

    // MARK: - Known terminals

    private static func focus(origin: TerminalOrigin, cwd: String?) -> Bool {
        let program = (origin.termProgram ?? "").lowercased()

        switch program {
        case "iterm.app":
            if let sessionId = origin.itermSessionId, focusITerm(sessionId: sessionId) { return true }
            return activate(bundleId: "com.googlecode.iterm2")

        case "apple_terminal":
            if focusAppleTerminal(cwd: cwd) { return true }
            return activate(bundleId: "com.apple.Terminal")

        case "vscode":
            // VS Code forks (Codium, Cursor, Windsurf) all report "vscode",
            // so open the folder with whichever is frontmost/installed.
            return openFolderInEditor(cwd: cwd)

        case "ghostty":
            return activate(bundleId: "com.mitchellh.ghostty")

        case "wezterm":
            if let pane = origin.weztermPane,
               run("/bin/sh", ["-lc", "wezterm cli activate-pane --pane-id \(pane)"]) {
                _ = activate(bundleId: "com.github.wez.wezterm")
                return true
            }
            return activate(bundleId: "com.github.wez.wezterm")

        case "kitty":
            if let windowId = origin.kittyWindowId,
               run("/bin/sh", ["-lc", "kitty @ focus-window --match id:\(windowId)"]) {
                _ = activate(bundleId: "net.kovidgoyal.kitty")
                return true
            }
            return activate(bundleId: "net.kovidgoyal.kitty")

        case "alacritty":
            return activate(bundleId: "org.alacritty")

        case "tabby":
            return activate(bundleId: "org.tabby")

        case "warpterminal", "warp":
            return activate(bundleId: "dev.warp.Warp-Stable")

        case "hyper":
            return activate(bundleId: "co.zeit.hyper")

        default:
            return false
        }
    }

    private static func focusITerm(sessionId: String) -> Bool {
        // ITERM_SESSION_ID looks like "w0t1p0:UUID"; the UUID is the session id.
        let uuid = sessionId.contains(":")
            ? String(sessionId.split(separator: ":").last ?? "")
            : sessionId
        guard !uuid.isEmpty else { return false }

        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "\(uuid)" then
                            select w
                            select t
                            select s
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "miss"
        """
        return runAppleScript(script) == "ok"
    }

    /// Terminal.app exposes a tty per tab but no session id, so the tab is
    /// matched through the tty of the `claude` process running in `cwd`.
    private static func focusAppleTerminal(cwd: String?) -> Bool {
        guard let cwd, let tty = claudeTTY(forCwd: cwd) else { return false }
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "miss"
        """
        return runAppleScript(script) == "ok"
    }

    /// pid of a `claude` process whose working directory is `cwd`, then its tty.
    private static func claudeTTY(forCwd cwd: String) -> String? {
        guard let listing = capture("/usr/sbin/lsof", ["-a", "-c", "claude", "-d", "cwd", "-Fpn"]) else {
            return nil
        }
        var currentPid: String?
        for line in listing.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = String(line.dropFirst())
            } else if line.hasPrefix("n"), String(line.dropFirst()) == cwd, let pid = currentPid {
                guard let tty = capture("/bin/ps", ["-o", "tty=", "-p", pid])?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !tty.isEmpty, tty != "??" else {
                    continue
                }
                return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            }
        }
        return nil
    }

    // MARK: - Fallbacks

    private static func openFolderInEditor(cwd: String?) -> Bool {
        guard let cwd else { return false }
        let candidates = [
            "com.microsoft.VSCode",
            "com.vscodium",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.exafunction.windsurf"
        ]
        for bundleId in candidates where appURL(bundleId) != nil {
            return open(path: cwd, bundleId: bundleId)
        }
        return false
    }

    private static func revealWithFallback(cwd: String?, target: RevealTarget) {
        guard let bundleId = target.bundleIdentifier else { return }
        if let cwd, open(path: cwd, bundleId: bundleId) { return }
        _ = activate(bundleId: bundleId)
    }

    // MARK: - Primitives

    private static func appURL(_ bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    private static func activate(bundleId: String) -> Bool {
        guard let url = appURL(bundleId) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    private static func open(path: String, bundleId: String) -> Bool {
        guard let appURL = appURL(bundleId) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
        return true
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Bool {
        capture(launchPath, arguments) != nil
    }

    private static func capture(_ launchPath: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
