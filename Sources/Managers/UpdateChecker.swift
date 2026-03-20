import Foundation
import AppKit
import Sparkle

@Observable
class UpdateChecker: NSObject {
    var updateAvailable = false
    var latestVersion: String?

    private var updaterController: SPUStandardUpdaterController?

    override init() {
        super.init()
    }

    func startPeriodicCheck() {
        // SPUStandardUpdaterController must be created on main thread
        // and after the app bundle is set up
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updaterController = controller
    }

    func stop() {
        // Sparkle handles its own cleanup
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func openDownloadPage() {
        // Sparkle handles download UI automatically
        checkForUpdates()
    }
}

extension UpdateChecker: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
        latestVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        updateAvailable = false
    }
}
