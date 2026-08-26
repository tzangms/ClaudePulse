import XCTest
import AppKit
import SwiftUI
@testable import ccpulse

/// The panel joins every space, fullscreen ones included, so it has to work out
/// for itself when a fullscreen app owns the screen and step aside.
final class FullscreenDetectionTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    private func window(pid: Int, layer: Int = 0, x: CGFloat = 0, y: CGFloat = 0,
                        width: CGFloat, height: CGFloat) -> [String: Any] {
        [
            kCGWindowLayer as String: layer,
            kCGWindowOwnerPID as String: pid,
            kCGWindowBounds as String: [
                "X": x, "Y": y, "Width": width, "Height": height
            ] as [String: Any]
        ]
    }

    func testDetectsAFullscreenWindow() {
        let windows = [window(pid: 42, width: 1728, height: 1117)]
        XCTAssertTrue(DynamicIslandPanel.screenIsCovered(
            by: windows, screenFrame: screen, ownPID: 1, frontmostPID: 42
        ))
    }

    /// A zoomed window stops at the menu bar and the Dock, so it is not the
    /// same thing as a fullscreen one.
    func testIgnoresAMaximizedWindow() {
        let windows = [window(pid: 42, y: 33, width: 1728, height: 1004)]
        XCTAssertFalse(DynamicIslandPanel.screenIsCovered(
            by: windows, screenFrame: screen, ownPID: 1, frontmostPID: 42
        ))
    }

    /// The window list reaches across spaces. A fullscreen app owns the space
    /// it is in and is frontmost there, which is what tells the two apart.
    func testIgnoresAFullscreenWindowOnAnotherSpace() {
        let windows = [window(pid: 99, width: 1728, height: 1117)]
        XCTAssertFalse(DynamicIslandPanel.screenIsCovered(
            by: windows, screenFrame: screen, ownPID: 1, frontmostPID: 42
        ))
    }

    /// Pulse's own panel never counts, whatever size it happens to be.
    func testIgnoresPulsesOwnWindows() {
        let windows = [window(pid: 1, width: 1728, height: 1117)]
        XCTAssertFalse(DynamicIslandPanel.screenIsCovered(
            by: windows, screenFrame: screen, ownPID: 1, frontmostPID: 1
        ))
    }

    /// The menu bar, the Dock and other panels live above the normal layer.
    func testIgnoresWindowsAboveTheNormalLayer() {
        let windows = [window(pid: 42, layer: 20, width: 1728, height: 1117)]
        XCTAssertFalse(DynamicIslandPanel.screenIsCovered(
            by: windows, screenFrame: screen, ownPID: 1, frontmostPID: 42
        ))
    }
}

/// The settings sheet is a hand-laid-out panel sized from its content, so it is
/// worth knowing it still lays out and still fits the window it opens in.
final class SettingsLayoutTests: XCTestCase {

    @MainActor
    func testSettingsSheetLaysOutAtItsFixedWidth() {
        let view = NSHostingView(rootView: SettingsView())
        view.sizingOptions = [.intrinsicContentSize]
        let size = view.fittingSize

        XCTAssertEqual(size.width, 280, accuracy: 1)
        XCTAssertGreaterThan(size.height, 300)
        // Anything approaching this would not fit on a laptop screen.
        XCTAssertLessThan(size.height, 720)
    }
}
