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
    @State private var sizeHover: TextSize?

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
        }
        .frame(width: 280)
        .fixedSize()
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
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
