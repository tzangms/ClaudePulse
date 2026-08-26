import SwiftUI
import AppKit

struct SettingsView: View {
    let settings = PanelSettings.shared
    var updateChecker: UpdateChecker?
    var onClose: (() -> Void)?

    @State private var positionHover: PanelPosition?
    @State private var toggleHovered = false
    @State private var checkUpdateHovered = false
    @State private var downloadHovered = false
    @State private var quitHovered = false
    @State private var coffeeHovered = false
    @State private var colorHover: AccentTheme?
    @State private var usageInstalled = StatusLineConfigurator().isInstalled()
    @State private var sizeHover: TextSize?
    @State private var detailHover: ActionDetail?
    @State private var labelHover: SessionLabelStyle?

    /// Says what the toggle actually does to the user's own configuration,
    /// since it takes over `statusLine` in `~/.claude/settings.json`.
    private var usageSubtitle: String {
        if !settings.showAccountUsage {
            return "Account limits are hidden from the panel"
        }
        if usageInstalled {
            return "Pulse owns the status line and reads your limits from it"
        }
        if StatusLineConfigurator().commandInPlace() != nil {
            return "Replaces your current status line to read your limits"
        }
        return "Uses the status line to read your 5-hour and weekly limits"
    }

    /// Turning account usage off has to hide the panel's limits as well as give
    /// the status line back: Pulse can also read the limits from Claude for
    /// Desktop's own records, so uninstalling alone would leave them on screen.
    private func toggleUsageTracking() {
        let configurator = StatusLineConfigurator()
        let turningOn = !settings.showAccountUsage
        do {
            if turningOn {
                try configurator.install(port: HookServer.currentPort ?? 19_280)
            } else if usageInstalled {
                try configurator.uninstall()
            }
            usageInstalled = configurator.isInstalled()
            settings.showAccountUsage = turningOn
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the status line"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom title bar
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            VStack(spacing: 16) {
                // Position selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 4) {
                        ForEach(PanelPosition.allCases, id: \.self) { pos in
                            let isSelected = settings.position == pos
                            let isHovered = positionHover == pos

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    settings.position = pos
                                }
                                NotificationCenter.default.post(name: .ccaniRepositionPanel, object: nil)
                            } label: {
                                Text(pos.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(isHovered ? 0.7 : 0.45))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? .white.opacity(0.12) : .white.opacity(isHovered ? 0.08 : 0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    positionHover = h ? pos : nil
                                }
                            }
                        }
                    }
                }

                // Keep Expanded toggle
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Expanded")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                        Text("Panel stays open without hovering")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()

                    // Custom toggle button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.pinExpanded.toggle()
                        }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(settings.pinExpanded ? settings.accentColor : .white.opacity(0.15))
                                .frame(width: 34, height: 20)

                            Circle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                                .offset(x: settings.pinExpanded ? 7 : -7)
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        toggleHovered = h
                    }
                }

                // Account usage — wraps Claude Code's statusLine so Pulse can
                // read the rate limits it reports.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account Usage")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                        Text(usageSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleUsageTracking()
                        }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(settings.showAccountUsage ? settings.accentColor : .white.opacity(0.15))
                                .frame(width: 34, height: 20)
                            Circle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                                .offset(x: settings.showAccountUsage ? 7 : -7)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Show Dock Icon toggle
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dock Icon")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                        Text("Show app icon in the Dock")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.showDockIcon.toggle()
                        }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(settings.showDockIcon ? settings.accentColor : .white.opacity(0.15))
                                .frame(width: 34, height: 20)
                            Circle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                                .offset(x: settings.showDockIcon ? 7 : -7)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Sound on Complete toggle
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound on Complete")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                        Text("Play a sound when work finishes")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.soundOnComplete.toggle()
                        }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(settings.soundOnComplete ? settings.accentColor : .white.opacity(0.15))
                                .frame(width: 34, height: 20)
                            Circle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                                .offset(x: settings.soundOnComplete ? 7 : -7)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if settings.soundOnComplete {
                    HStack {
                        Text("Sound")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.soundName },
                            set: { newValue in
                                settings.soundName = newValue
                                NSSound(named: .init(newValue))?.play()
                            }
                        )) {
                            ForEach(PanelSettings.availableSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                }

                // Session duration
                SettingsToggleRow(
                    title: "Session Duration",
                    subtitle: "Count how long a session has been running",
                    isOn: Binding(get: { settings.showSessionDuration },
                                  set: { settings.showSessionDuration = $0 })
                )

                // Show over fullscreen
                SettingsToggleRow(
                    title: "Show Over Fullscreen",
                    subtitle: "Float above fullscreen apps like video players",
                    isOn: Binding(get: { settings.showOverFullscreen },
                                  set: { settings.showOverFullscreen = $0 })
                )

                // Permission control
                SettingsToggleRow(
                    title: "Answer Permissions in Pulse",
                    subtitle: "Show Allow / Allow all / Deny in the panel",
                    isOn: Binding(get: { settings.permissionControl },
                                  set: { settings.permissionControl = $0 })
                )

                if settings.permissionControl {
                    HStack {
                        Text("Wait")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.permissionTimeout },
                            set: { newValue in
                                settings.permissionTimeout = newValue
                                NotificationCenter.default.post(name: .ccaniHooksNeedSync, object: nil)
                            }
                        )) {
                            Text("30s").tag(30.0)
                            Text("1 min").tag(60.0)
                            Text("2 min").tag(120.0)
                            Text("5 min").tag(300.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                    Text("After that the prompt goes back to the terminal.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Fallback reveal target
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reveal In")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                        Text("Auto: the session's terminal, else Claude")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.revealTarget },
                        set: { settings.revealTarget = $0 }
                    )) {
                        ForEach(RevealTarget.allCases, id: \.self) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                // Accent color selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Color")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 8) {
                        ForEach(AccentTheme.allCases, id: \.self) { theme in
                            let isSelected = settings.accentTheme == theme
                            let isHovered = colorHover == theme

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    settings.accentTheme = theme
                                }
                            } label: {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(.white, lineWidth: isSelected ? 2 : 0)
                                            .frame(width: 24, height: 24)
                                    )
                                    .scaleEffect(isHovered ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    colorHover = h ? theme : nil
                                }
                            }
                        }
                        Spacer()
                    }
                }

                // Text size selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 4) {
                        ForEach(TextSize.allCases, id: \.self) { size in
                            let isSelected = settings.textSize == size
                            let isHovered = sizeHover == size

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    settings.textSize = size
                                }
                            } label: {
                                Text(size.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(isHovered ? 0.7 : 0.45))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? .white.opacity(0.12) : .white.opacity(isHovered ? 0.08 : 0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    sizeHover = h ? size : nil
                                }
                            }
                        }
                    }
                }

                // Panel width — S/M/L scales the type, this scales the panel,
                // so a wide command or a long session title can be read.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Width")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Text("\(Int(settings.panelWidth)) pt")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Slider(
                        value: Binding(
                            get: { settings.panelWidth },
                            set: { settings.panelWidth = ($0 / 10).rounded() * 10 }
                        ),
                        in: PanelSettings.minimumPanelWidth...PanelSettings.maximumPanelWidth
                    )
                    .controlSize(.small)
                    .tint(settings.accentColor)
                }

                // How much of a waiting permission prompt is shown
                SettingsSegmentedRow(
                    title: "Action Detail",
                    subtitle: "How much a prompt shows while it waits",
                    options: ActionDetail.allCases,
                    label: { $0.displayName },
                    selection: Binding(get: { settings.actionDetail },
                                       set: { settings.actionDetail = $0 }),
                    hovered: $detailHover
                )

                // What a session row leads with
                SettingsSegmentedRow(
                    title: "Session Name",
                    subtitle: "Claude's session title, or the folder",
                    options: SessionLabelStyle.allCases,
                    label: { $0.displayName },
                    selection: Binding(get: { settings.sessionLabelStyle },
                                       set: { settings.sessionLabelStyle = $0 }),
                    hovered: $labelHover
                )

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)

                // Updates section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Updates")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack {
                        if let checker = updateChecker, checker.updateAvailable,
                           let version = checker.latestVersion {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("v\(version) available")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                checker.checkForUpdates()
                            } label: {
                                Text("Update")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(downloadHovered ? .white : .white.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(.white.opacity(downloadHovered ? 0.15 : 0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeInOut(duration: 0.1)) { downloadHovered = h }
                            }
                        } else {
                            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                            Text("v\(currentVersion)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                            Spacer()
                            Button {
                                updateChecker?.checkForUpdates()
                            } label: {
                                Text("Check Now")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(checkUpdateHovered ? .white : .white.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(.white.opacity(checkUpdateHovered ? 0.15 : 0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeInOut(duration: 0.1)) { checkUpdateHovered = h }
                            }
                        }
                    }
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)

                // Bottom row: Buy Me a Coffee + Quit
                HStack {
                    Button {
                        if let url = URL(string: "https://www.buymeacoffee.com/tzangms") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("☕")
                                .font(.system(size: 11))
                            Text("Buy me a coffee")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(coffeeHovered ? .white : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.1)) { coffeeHovered = h }
                    }

                    Spacer()

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(quitHovered ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white.opacity(quitHovered ? 0.15 : 0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.1)) { quitHovered = h }
                    }
                }
            }
            .padding(16)
            .modifier(ScrollingSheetBody())
        }
        .frame(width: 280)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The pill toggle used across the settings sheet.
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    private let settings = PanelSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
            } label: {
                ZStack {
                    Capsule()
                        .fill(isOn ? settings.accentColor : .white.opacity(0.15))
                        .frame(width: 34, height: 20)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .offset(x: isOn ? 7 : -7)
                }
            }
            .buttonStyle(.plain)
        }
    }
}


/// Lets the settings scroll. There are enough settings now that the sheet would
/// otherwise run off the bottom of a laptop screen at full height.
struct ScrollingSheetBody: ViewModifier {
    /// Tall enough to show most of the sheet at once, short enough to leave the
    /// window on screen next to the menu bar and the Dock.
    static let maximumHeight: CGFloat = 620

    func body(content: Content) -> some View {
        ScrollView(.vertical) { content }
            .frame(maxHeight: Self.maximumHeight)
            .scrollBounceBehavior(.basedOnSize)
    }
}

/// The small segmented control the settings sheet uses for short choices.
struct SettingsSegmentedRow<Value: Hashable>: View {
    let title: String
    var subtitle: String?
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    @Binding var hovered: Value?
    private let settings = PanelSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    let isHovered = hovered == option

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = option }
                    } label: {
                        Text(label(option))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .white.opacity(isHovered ? 0.7 : 0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? .white.opacity(0.12) : .white.opacity(isHovered ? 0.08 : 0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.1)) { hovered = h ? option : nil }
                    }
                }
            }
        }
    }
}

class SettingsWindowController {
    private var panel: NSPanel?

    func showSettings(updateChecker: UpdateChecker) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let settingsView = SettingsView(
            updateChecker: updateChecker,
            onClose: { [weak panel] in
                panel?.orderOut(nil)
            }
        )
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView

        // Resize panel to fit actual content size
        let fittingSize = hostingView.fittingSize
        let width = ceil(max(fittingSize.width, 280))
        let height = ceil(fittingSize.height)
        panel.setContentSize(CGSize(width: width, height: height))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }
}
