import SwiftUI
import AppKit

class DynamicIslandPanel: NSPanel {
    /// Fixed height for bottom positions — large enough for any expanded content.
    /// The SwiftUI content is bottom-aligned within this fixed frame,
    /// eliminating the frame-resize ↔ hover race condition.
    static let bottomFixedHeight: CGFloat = 400

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
            // Without .fullScreenAuxiliary the panel stays out of fullscreen spaces.
            collectionBehavior = [.canJoinAllSpaces, .stationary]
            level = .floating
        }
        if isVisible {
            orderFrontRegardless()
        }
    }

    func repositionForCurrentSettings() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 12

        let newFrame: NSRect
        switch PanelSettings.shared.position {
        case .topCenter:
            let origin = NSPoint(
                x: screenFrame.midX - frame.width / 2,
                y: screenFrame.maxY - frame.height - 8
            )
            newFrame = NSRect(origin: origin, size: frame.size)
        case .bottomLeft, .bottomRight:
            let width = max(frame.width, 280)
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
        let newWidth = ceil(max(contentSize.width, 280))
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
