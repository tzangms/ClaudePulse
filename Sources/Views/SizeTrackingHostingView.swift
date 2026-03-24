import SwiftUI
import AppKit

class SizeTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((CGSize) -> Void)?
    private var lastReportedSize: CGSize = .zero

    override func layout() {
        super.layout()
        // Use ceil to avoid fractional sizes that can clip content on some macOS versions
        let fitting = CGSize(
            width: ceil(fittingSize.width),
            height: ceil(fittingSize.height)
        )
        if fitting != lastReportedSize {
            lastReportedSize = fitting
            onSizeChange?(fitting)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // For bottom positions the panel has a fixed tall frame.
        // Pass through clicks in the transparent area above the content
        // so users can interact with windows behind the panel.
        if PanelSettings.shared.position != .topCenter {
            let contentHeight = lastReportedSize.height
            // AppKit coordinates: y=0 is at the bottom of the view.
            // Content is bottom-aligned, occupying y: 0 ..< contentHeight.
            if point.y > contentHeight {
                return nil
            }
        }
        return super.hitTest(point)
    }
}
