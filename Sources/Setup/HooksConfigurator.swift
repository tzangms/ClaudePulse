import Foundation
import AppKit

struct HooksConfigurator {
    private let settingsPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    /// Events Pulse listens to. `PermissionRequest` is the only one that can
    /// block, and only while "Answer permissions in Pulse" is enabled.
    static let events = [
        "SessionStart", "SessionEnd",
        "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PostToolUseFailure", "Notification", "CwdChanged",
        "PermissionRequest", "PermissionDenied", "Stop"
    ]

    /// Environment variables the hook forwards as headers so Pulse can find the
    /// terminal window a session belongs to.
    private static let envHeaders: [(header: String, variable: String)] = [
        ("X-Pulse-Term-Program", "TERM_PROGRAM"),
        ("X-Pulse-Term-Session", "TERM_SESSION_ID"),
        ("X-Pulse-Iterm-Session", "ITERM_SESSION_ID"),
        ("X-Pulse-Wezterm-Pane", "WEZTERM_PANE"),
        ("X-Pulse-Kitty-Window", "KITTY_WINDOW_ID")
    ]

    func needsSetup() -> Bool {
        guard let json = readSettings(), let hooks = json["hooks"] as? [String: Any] else {
            return true
        }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard let hookList = entry["hooks"] as? [[String: Any]] else { continue }
                if hookList.contains(where: { isPulseHook($0) }) { return false }
            }
        }
        return true
    }

    func promptAndInstall(port: UInt16) {
        let alert = NSAlert()
        alert.messageText = "Configure Claude Code Hooks?"
        alert.informativeText = "Pulse needs to add hooks to ~/.claude/settings.json to receive events from Claude Code. This will not overwrite your existing hooks."
        // Pulse runs as an accessory app, so without this the alert opens
        // behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
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

    /// Rewrites Pulse's hook entries when anything they encode has changed —
    /// the port the server ended up on, or the permission timeout.
    /// Safe to call on every launch and whenever settings change.
    func syncIfNeeded(port: UInt16) {
        guard !needsSetup() else { return }
        guard let json = readSettings(),
              let hooks = json["hooks"] as? [String: Any] else { return }

        let expectedURL = Self.url(for: port)
        var upToDate = true
        var seenEvents = Set<String>()

        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard let hookList = entry["hooks"] as? [[String: Any]] else { continue }
                for hook in hookList where isPulseHook(hook) {
                    seenEvents.insert(event)
                    if hook["type"] as? String != "http" { upToDate = false }
                    if hook["url"] as? String != expectedURL { upToDate = false }
                    let expectedTimeout = Self.timeout(for: event)
                    if (hook["timeout"] as? Double) != expectedTimeout { upToDate = false }
                }
            }
        }
        if seenEvents != Set(Self.events) { upToDate = false }
        guard !upToDate else { return }

        try? install(port: port)
        print("Pulse hooks re-synced for port \(port)")
    }

    // MARK: - Install

    private func install(port: UInt16) throws {
        var json: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: settingsPath.path) {
            let data = try Data(contentsOf: settingsPath)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError.malformedSettings
            }
            json = existing

            // Backup existing settings before modifying so users can recover
            // if anything (including future versions of this code) goes wrong.
            let backupURL = settingsPath.deletingLastPathComponent()
                .appendingPathComponent("settings.json.ccpulse-backup")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: settingsPath, to: backupURL)
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        // Drop every hook Pulse previously wrote (including the old curl ones)
        // so re-running never stacks duplicates.
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var entry in entries {
                guard let hookList = entry["hooks"] as? [[String: Any]] else {
                    kept.append(entry)
                    continue
                }
                let remaining = hookList.filter { !isPulseHook($0) }
                if remaining.isEmpty { continue }
                entry["hooks"] = remaining
                kept.append(entry)
            }
            if kept.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = kept
            }
        }

        for event in Self.events {
            let entry: [String: Any] = [
                "matcher": "",
                "hooks": [Self.hookDefinition(port: port, event: event)]
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

    /// Removes every Pulse hook — used when the user turns the integration off.
    func uninstall() throws {
        guard var json = readSettings(), var hooks = json["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var entry in entries {
                guard let hookList = entry["hooks"] as? [[String: Any]] else {
                    kept.append(entry)
                    continue
                }
                let remaining = hookList.filter { !isPulseHook($0) }
                if remaining.isEmpty { continue }
                entry["hooks"] = remaining
                kept.append(entry)
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        json["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsPath, options: .atomic)
    }

    // MARK: - Hook definition

    static func url(for port: UInt16) -> String {
        "http://127.0.0.1:\(port)/hook"
    }

    /// Seconds Claude Code waits for Pulse to answer. Everything but a
    /// permission prompt is answered immediately, so those stay short: if Pulse
    /// is wedged or gone, Claude Code moves on almost instantly.
    static func timeout(for event: String) -> Double {
        guard event == "PermissionRequest" else { return 3 }
        guard PanelSettings.shared.permissionControl else { return 3 }
        // Give the panel its full window plus slack for the round trip.
        return max(10, PanelSettings.shared.permissionTimeout + 10)
    }

    static func hookDefinition(port: UInt16, event: String) -> [String: Any] {
        var headers: [String: String] = ["X-Pulse-Hook": "1"]
        for (header, variable) in envHeaders {
            headers[header] = "$\(variable)"
        }
        return [
            "type": "http",
            "url": url(for: port),
            "timeout": timeout(for: event),
            "headers": headers,
            "allowedEnvVars": envHeaders.map(\.variable)
        ]
    }

    // MARK: - Helpers

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// True for hooks Pulse owns: the current HTTP ones and the legacy curl
    /// commands written by versions <= 0.2.7.
    private func isPulseHook(_ hook: [String: Any]) -> Bool {
        if let headers = hook["headers"] as? [String: Any], headers["X-Pulse-Hook"] != nil { return true }
        if let url = hook["url"] as? String, url.contains("/hook"), url.contains("1928") { return true }
        if let command = hook["command"] as? String, command.contains("ccani") { return true }
        return false
    }

    enum ConfigError: Error, LocalizedError {
        case malformedSettings

        var errorDescription: String? {
            "~/.claude/settings.json contains malformed JSON. Please fix it manually and restart Pulse."
        }
    }
}
