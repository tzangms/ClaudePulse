import SwiftUI
import AppKit

class DynamicIslandPanel: NSPanel {
    /// Height for bottom positions — large enough for any expanded content.
    /// The SwiftUI content is bottom-aligned within this fixed frame,
    /// eliminating the frame-resize ↔ hover race condition. It grows with the
    /// action-detail setting, which is what makes the content tall.
    static var bottomFixedHeight: CGFloat {
        PanelSettings.shared.actionDetail.bottomPanelHeight
    }

    /// True while the active space belongs to a fullscreen app. The panel joins
    /// every space so it follows the user around, and that includes fullscreen
    /// ones — so unless the user asked for it, it hides itself there instead.
    private var activeSpaceIsFullscreen = false
    private var hiddenForFullscreen = false

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        self.contentView = contentView
        observeSpaceChanges()
        applyWindowBehavior()
        repositionForCurrentSettings()
    }

    /// True while a permission prompt is waiting: the panel then floats over
    /// fullscreen apps even when the user opted out of that for normal use.
    var isUrgent = false {
        didSet {
            guard isUrgent != oldValue else { return }
            applyWindowBehavior()
        }
    }

    /// Whether the panel joins fullscreen spaces, and how high it floats.
    func applyWindowBehavior() {
        let overFullscreen = isUrgent || PanelSettings.shared.showOverFullscreen
        if overFullscreen {
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            // Above the menu bar / fullscreen chrome so the prompt is reachable.
            level = isUrgent ? .screenSaver : .floating
        } else {
            // Without .fullScreenAuxiliary the panel stays out of fullscreen
            // spaces a *window* owns, but a fullscreen video player is often
            // just a borderless window filling the screen on the current space,
            // and .canJoinAllSpaces puts the panel on top of it either way.
            collectionBehavior = [.canJoinAllSpaces, .stationary]
            level = .floating
        }
        applyFullscreenVisibility()
    }

    // MARK: - Fullscreen spaces

    private func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeSpaceChanged() {
        applyFullscreenVisibility()
    }

    /// Hides the panel while a fullscreen app owns the screen, unless the user
    /// asked for it there or a prompt is waiting on them.
    func applyFullscreenVisibility() {
        activeSpaceIsFullscreen = Self.screenIsCoveredByAnotherApp()
        let allowed = isUrgent || PanelSettings.shared.showOverFullscreen

        if activeSpaceIsFullscreen && !allowed {
            if isVisible {
                hiddenForFullscreen = true
                orderOut(nil)
            }
        } else if hiddenForFullscreen {
            hiddenForFullscreen = false
            orderFrontRegardless()
        } else if isVisible {
            orderFrontRegardless()
        }
    }

    /// Show or hide the panel because the user asked to, rather than because a
    /// fullscreen app took the screen.
    func setUserVisible(_ visible: Bool) {
        hiddenForFullscreen = false
        if visible {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    /// True when another application has a window covering the whole screen —
    /// a fullscreen space, or a video player that simply fills it.
    ///
    /// Only window geometry is read, which needs no screen-recording access.
    static func screenIsCoveredByAnotherApp(screen: NSScreen? = NSScreen.main) -> Bool {
        guard let screen else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return screenIsCovered(
            by: windows,
            screenFrame: screen.frame,
            ownPID: Int(ProcessInfo.processInfo.processIdentifier),
            frontmostPID: NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) }
        )
    }

    /// The geometry half of the test, kept apart from the window server.
    ///
    /// A fullscreen app owns the space it is in and is always the frontmost
    /// one, which is what separates it from the maximized windows sitting on
    /// other spaces that the window list also reports.
    static func screenIsCovered(
        by windows: [[String: Any]],
        screenFrame: CGRect,
        ownPID: Int,
        frontmostPID: Int?
    ) -> Bool {
        for window in windows {
            // Layer 0 is the normal window layer: the menu bar, the Dock and
            // floating panels (Pulse included) all sit above it.
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid != ownPID,
                  frontmostPID == nil || pid == frontmostPID,
                  let frameValue = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: frameValue as CFDictionary) else { continue }

            if abs(frame.width - screenFrame.width) < 2 && abs(frame.height - screenFrame.height) < 2 {
                return true
            }
        }
        return false
    }

    func repositionForCurrentSettings() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 12
        let contentWidth = PanelSettings.shared.contentWidth

        let newFrame: NSRect
        switch PanelSettings.shared.position {
        case .topCenter:
            let width = contentWidth
            let origin = NSPoint(
                x: screenFrame.midX - width / 2,
                y: screenFrame.maxY - frame.height - 8
            )
            newFrame = NSRect(origin: origin, size: CGSize(width: width, height: frame.height))
        case .bottomLeft, .bottomRight:
            let width = contentWidth
            let x = PanelSettings.shared.position == .bottomLeft
                ? screenFrame.minX + margin
                : screenFrame.maxX - width - margin
            newFrame = NSRect(
                x: x,
                y: screenFrame.minY + margin,
                width: width,
                height: Self.bottomFixedHeight
            )
        }
        setFrame(newFrame, display: true)
    }

    func updateFrameForContentSize(_ contentSize: CGSize) {
        // Bottom positions use a fixed frame — no updates needed.
        guard PanelSettings.shared.position == .topCenter else { return }
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let newWidth = ceil(max(contentSize.width, PanelSettings.shared.contentWidth))
        let newHeight = ceil(contentSize.height)

        let topY = frame.origin.y + frame.size.height
        let newOrigin = NSPoint(
            x: screenFrame.midX - newWidth / 2,
            y: topY - newHeight
        )

        let newFrame = NSRect(origin: newOrigin, size: CGSize(width: newWidth, height: newHeight))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }
}
