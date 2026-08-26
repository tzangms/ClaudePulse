import AppKit
import Foundation

/// Points Claude Code's `statusLine` at Pulse.
///
/// Claude Code reports account-wide rate limits to exactly one place, its status
/// line command, and the setting holds a single command — not a list. So a tool
/// that wants the data has to own the slot. Pulse takes it outright rather than
/// wrapping whatever was there: chaining would mean running another tool's
/// binary from inside Pulse and breaking whenever that tool moved or changed.
///
/// The consequence is deliberate and worth stating plainly to the user:
/// installing this replaces any existing status line, and switching back means
/// re-installing from the other tool.
struct StatusLineConfigurator {
    var settingsPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    var scriptPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ccani/statusline.sh")

    func isInstalled() -> Bool {
        currentCommand() == scriptPath.path
    }

    /// True when Pulse owns the slot but the script on disk is not the one this
    /// version writes — an app update, or a half-finished install.
    func needsScriptRefresh(port: UInt16) -> Bool {
        guard isInstalled() else { return false }
        let onDisk = try? String(contentsOf: scriptPath, encoding: .utf8)
        return onDisk != scriptBody(port: port)
    }

    /// Rewrites the script without touching settings or asking again: the user
    /// already agreed to Pulse owning the status line.
    func refreshScript(port: UInt16) throws {
        try writeScript(port: port)
    }

    /// The command that would be replaced, so the user can be told what they
    /// are giving up before they agree to it.
    func commandInPlace() -> String? {
        guard let command = currentCommand(), command != scriptPath.path else { return nil }
        return command
    }

    private func currentCommand() -> String? {
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else { return nil }
        return command
    }

    // MARK: - Prompt

    /// Asked once. Taking over the status line is a visible change to the
    /// user's terminal, so it is never done silently.
    func promptAndInstall(port: UInt16) {
        let alert = NSAlert()
        alert.messageText = "Show account usage in Pulse?"

        var text = """
        Claude Code reports your 5-hour and weekly limits to one place only: its \
        status line. The setting holds a single command, so Pulse has to take it.

        """
        if let existing = commandInPlace() {
            text += """

            This replaces your current status line:

            \(existing)

            Pulse will print its own line instead. To go back, re-install the \
            status line from whichever tool set it.
            """
        } else {
            text += "\nPulse will print a short line with context and limit usage."
        }
        text += "\n\n~/.claude/settings.json is backed up first."
        alert.informativeText = text

        // Pulse runs as an accessory app, so without this the alert opens
        // behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        alert.addButton(withTitle: "Use Pulse's Status Line")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else {
            PanelSettings.shared.statusLinePromptDismissed = true
            return
        }
        do {
            try install(port: port)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not set up the status line"
            failure.informativeText = error.localizedDescription
            failure.alertStyle = .warning
            failure.runModal()
        }
    }

    // MARK: - Install

    func install(port: UInt16) throws {
        try writeScript(port: port)

        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath.path) {
            let data = try Data(contentsOf: settingsPath)
            guard let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError.malformedSettings
            }
            json = existing
            try backUpSettings()
        }

        // Keys like `padding` describe how Claude Code lays the line out, not
        // who produces it, so they are left alone.
        var statusLine = json["statusLine"] as? [String: Any] ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = scriptPath.path
        json["statusLine"] = statusLine

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: settingsPath, options: .atomic)
    }

    /// Removes the status line entirely. Pulse never recorded what was there
    /// before, so it cannot put it back — the other tool re-installs itself.
    func uninstall() throws {
        guard let data = try? Data(contentsOf: settingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              statusLine["command"] as? String == scriptPath.path else { return }

        try backUpSettings()
        json.removeValue(forKey: "statusLine")

        let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: settingsPath, options: .atomic)
        try? FileManager.default.removeItem(at: scriptPath)
    }

    // MARK: - Script

    /// The script posts the payload and prints whatever Pulse sends back, so
    /// the line's content is decided in Swift rather than in shell. If Pulse is
    /// not running, curl fails and the status line is simply empty.
    private func scriptBody(port: UInt16) -> String {
        """
        #!/bin/sh
        # Installed by Pulse. Sends Claude Code's status line payload to the app
        # and prints the line the app renders from it.
        # Delete this file and the "statusLine" key in ~/.claude/settings.json to
        # remove it, or turn off Account Usage in Pulse's settings.

        curl -sf -m 1 -X POST \\
            -H 'Content-Type: application/json' --data-binary @- \\
            "http://localhost:$(cat ~/.ccani/port 2>/dev/null || echo \(port))/statusline" \\
            2>/dev/null || true

        """
    }

    private func writeScript(port: UInt16) throws {
        let script = scriptBody(port: port)

        try FileManager.default.createDirectory(
            at: scriptPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
    }

    private func backUpSettings() throws {
        let backup = settingsPath.deletingLastPathComponent()
            .appendingPathComponent("settings.json.ccpulse-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: settingsPath, to: backup)
    }

    enum ConfigError: Error, LocalizedError {
        case malformedSettings

        var errorDescription: String? {
            "~/.claude/settings.json contains malformed JSON. Please fix it manually and restart Pulse."
        }
    }
}
