import Foundation
import SwiftUI

enum PanelPosition: String, CaseIterable {
    case topCenter = "top-center"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"

    var displayName: String {
        switch self {
        case .topCenter: return "Top Center"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum AccentTheme: String, CaseIterable {
    case purple
    case cyan
    case green
    case orange
    case pink

    var displayName: String {
        switch self {
        case .purple: return "Purple"
        case .cyan: return "Cyan"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        }
    }

    var color: Color {
        switch self {
        case .purple: return Color(red: 0.85, green: 0.5, blue: 1.0)
        case .cyan: return Color(red: 0.3, green: 0.85, blue: 1.0)
        case .green: return Color(red: 0.3, green: 0.95, blue: 0.6)
        case .orange: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .pink: return Color(red: 1.0, green: 0.4, blue: 0.6)
        }
    }
}

enum TextSize: String, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.15
        }
    }
}


/// How much of a permission prompt is shown while it waits for an answer.
/// The one-line summary is enough for a familiar command; deciding on a long
/// diff, a URL or a full plan needs the whole thing.
enum ActionDetail: String, CaseIterable {
    case compact
    case standard
    case full

    var displayName: String {
        switch self {
        case .compact: return "S"
        case .standard: return "M"
        case .full: return "L"
        }
    }

    /// Lines of detail shown before truncation.
    var lineLimit: Int {
        switch self {
        case .compact: return 2
        case .standard: return 6
        case .full: return 24
        }
    }

    /// Room the panel reserves at the bottom screen positions, where its frame
    /// is fixed: a fuller prompt needs a taller frame to sit in.
    var bottomPanelHeight: CGFloat {
        switch self {
        case .compact: return 400
        case .standard: return 480
        case .full: return 700
        }
    }

    /// Whether the whole tool input is worth showing rather than the single
    /// field that usually carries the meaning.
    var showsWholeInput: Bool { self == .full }
}

/// What a session row calls itself.
enum SessionLabelStyle: String, CaseIterable {
    /// The working directory's folder name — what Pulse has always shown.
    case project
    /// Claude Code's own session title, with the folder underneath.
    case title

    var displayName: String {
        switch self {
        case .project: return "Repo"
        case .title: return "Session"
        }
    }
}

/// Where clicking a session takes you.
enum RevealTarget: String, CaseIterable {
    /// Focus the terminal the session actually runs in; fall back to Claude
    /// for Desktop when Pulse cannot identify one.
    case auto
    case claudeDesktop
    case finder
    case terminal
    case iterm
    case ghostty
    case vscode
    case codium
    case cursor

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .claudeDesktop: return "Claude"
        case .finder: return "Finder"
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .vscode: return "VS Code"
        case .codium: return "VSCodium"
        case .cursor: return "Cursor"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .auto: return nil
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .finder: return "com.apple.finder"
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .vscode: return "com.microsoft.VSCode"
        case .codium: return "com.vscodium"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        }
    }
}

@Observable
class PanelSettings {
    static let shared = PanelSettings()

    var position: PanelPosition {
        didSet { UserDefaults.standard.set(position.rawValue, forKey: "panelPosition") }
    }

    var pinExpanded: Bool {
        didSet { UserDefaults.standard.set(pinExpanded, forKey: "pinExpanded") }
    }

    var accentTheme: AccentTheme {
        didSet { UserDefaults.standard.set(accentTheme.rawValue, forKey: "accentTheme") }
    }

    var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: "textSize") }
    }

    /// Panel width in points. S/M/L scales the type; this scales the panel,
    /// so a long command or a wide session list can be read without changing
    /// the font size.
    var panelWidth: Double {
        didSet {
            UserDefaults.standard.set(panelWidth, forKey: "panelWidth")
            NotificationCenter.default.post(name: .ccaniRepositionPanel, object: nil)
        }
    }

    /// How much of a waiting permission prompt is shown.
    var actionDetail: ActionDetail {
        didSet {
            UserDefaults.standard.set(actionDetail.rawValue, forKey: "actionDetail")
            // The bottom positions size their frame from this.
            NotificationCenter.default.post(name: .ccaniRepositionPanel, object: nil)
        }
    }

    /// Whether rows and the capsule count how long a session has been running.
    var showSessionDuration: Bool {
        didSet { UserDefaults.standard.set(showSessionDuration, forKey: "showSessionDuration") }
    }

    /// Whether session rows lead with Claude Code's session title or the folder.
    var sessionLabelStyle: SessionLabelStyle {
        didSet { UserDefaults.standard.set(sessionLabelStyle.rawValue, forKey: "sessionLabelStyle") }
    }

    /// Whether the account-wide limits are shown in the panel at all. Pulse can
    /// read them from Claude for Desktop's records without owning the status
    /// line, so this has to gate the display rather than the status line alone.
    var showAccountUsage: Bool {
        didSet { UserDefaults.standard.set(showAccountUsage, forKey: "showAccountUsage") }
    }

    var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        }
    }

    /// Set when the user declines the status line prompt, so it is asked once.
    var statusLinePromptDismissed: Bool {
        didSet { UserDefaults.standard.set(statusLinePromptDismissed, forKey: "statusLinePromptDismissed") }
    }

    var soundOnComplete: Bool {
        didSet { UserDefaults.standard.set(soundOnComplete, forKey: "soundOnComplete") }
    }

    var soundName: String {
        didSet { UserDefaults.standard.set(soundName, forKey: "soundName") }
    }

    /// Float above fullscreen apps (video, Xcode fullscreen...). Off by default;
    /// permission prompts still force themselves to the front when they appear.
    var showOverFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(showOverFullscreen, forKey: "showOverFullscreen")
            NotificationCenter.default.post(name: .ccaniPanelBehaviorChanged, object: nil)
        }
    }

    /// Answer Claude Code permission prompts from the panel instead of the terminal.
    var permissionControl: Bool {
        didSet {
            UserDefaults.standard.set(permissionControl, forKey: "permissionControl")
            NotificationCenter.default.post(name: .ccaniHooksNeedSync, object: nil)
        }
    }

    /// How long a permission prompt waits in the panel before handing control
    /// back to the terminal.
    var permissionTimeout: Double {
        didSet { UserDefaults.standard.set(permissionTimeout, forKey: "permissionTimeout") }
    }

    var revealTarget: RevealTarget {
        didSet { UserDefaults.standard.set(revealTarget.rawValue, forKey: "revealTarget") }
    }

    static let availableSounds = [
        "Glass", "Ping", "Pop", "Hero", "Blow",
        "Bottle", "Frog", "Funk", "Morse",
        "Purr", "Sosumi", "Submarine", "Tink", "Basso"
    ]

    static let defaultPanelWidth: Double = 280
    static let minimumPanelWidth: Double = 240
    static let maximumPanelWidth: Double = 720

    var accentColor: Color { accentTheme.color }

    /// Width the panel's content lays out at, clamped to what the panel can
    /// actually be given a stored value from an older build or another screen.
    var contentWidth: CGFloat {
        CGFloat(min(max(panelWidth, Self.minimumPanelWidth), Self.maximumPanelWidth))
    }

    private init() {
        let posRaw = UserDefaults.standard.string(forKey: "panelPosition") ?? PanelPosition.topCenter.rawValue
        self.position = PanelPosition(rawValue: posRaw) ?? .topCenter
        self.pinExpanded = UserDefaults.standard.bool(forKey: "pinExpanded")
        let themeRaw = UserDefaults.standard.string(forKey: "accentTheme") ?? AccentTheme.purple.rawValue
        self.accentTheme = AccentTheme(rawValue: themeRaw) ?? .purple
        let sizeRaw = UserDefaults.standard.string(forKey: "textSize") ?? TextSize.medium.rawValue
        self.textSize = TextSize(rawValue: sizeRaw) ?? .medium
        let storedWidth = UserDefaults.standard.double(forKey: "panelWidth")
        self.panelWidth = storedWidth > 0 ? storedWidth : Self.defaultPanelWidth
        let detailRaw = UserDefaults.standard.string(forKey: "actionDetail") ?? ActionDetail.standard.rawValue
        self.actionDetail = ActionDetail(rawValue: detailRaw) ?? .standard
        let labelRaw = UserDefaults.standard.string(forKey: "sessionLabelStyle") ?? SessionLabelStyle.project.rawValue
        self.sessionLabelStyle = SessionLabelStyle(rawValue: labelRaw) ?? .project
        // Absent means on for both: Pulse showed these before the switches existed.
        self.showSessionDuration = UserDefaults.standard.object(forKey: "showSessionDuration") == nil
            || UserDefaults.standard.bool(forKey: "showSessionDuration")
        self.showAccountUsage = UserDefaults.standard.object(forKey: "showAccountUsage") == nil
            || UserDefaults.standard.bool(forKey: "showAccountUsage")
        self.showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        self.statusLinePromptDismissed = UserDefaults.standard.bool(forKey: "statusLinePromptDismissed")
        self.soundOnComplete = UserDefaults.standard.bool(forKey: "soundOnComplete")
        self.soundName = UserDefaults.standard.string(forKey: "soundName") ?? "Glass"
        self.showOverFullscreen = UserDefaults.standard.bool(forKey: "showOverFullscreen")
        self.permissionControl = UserDefaults.standard.bool(forKey: "permissionControl")
        let storedTimeout = UserDefaults.standard.double(forKey: "permissionTimeout")
        self.permissionTimeout = storedTimeout > 0 ? storedTimeout : 120
        let revealRaw = UserDefaults.standard.string(forKey: "revealTarget") ?? RevealTarget.auto.rawValue
        self.revealTarget = RevealTarget(rawValue: revealRaw) ?? .auto
    }
}
