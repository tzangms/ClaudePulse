import SwiftUI
import AppKit

class DynamicIslandPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        self.contentView = contentView
        positionAtTopCenter()
    }

    func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.maxY - frame.height - 8
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func resizeForExpanded(_ expanded: Bool) {
        let newHeight: CGFloat = expanded ? 240 : 36
        var newFrame = frame
        let oldHeight = newFrame.height
        newFrame.size.height = newHeight
        newFrame.origin.y -= (newHeight - oldHeight)
        setFrame(newFrame, display: true, animate: true)
    }
}
