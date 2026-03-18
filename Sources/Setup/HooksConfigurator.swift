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
