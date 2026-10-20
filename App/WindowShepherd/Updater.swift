import AppKit
import Sparkle

/// Check for Updates, via Sparkle (the only network traffic the app makes).
/// Updates must be signed with the project's key; until a build carries the
/// public key (SUPublicEDKey), the menu item opens the releases page instead.
@MainActor
final class Updater {
    private var controller: SPUStandardUpdaterController?
    static let releasesPage = URL(string: "https://github.com/cabaynes/window-shepherd/releases")!

    init() {
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
    }

    func checkForUpdates() {
        if let controller {
            NSApp.activate()
            controller.checkForUpdates(nil)
        } else {
            NSWorkspace.shared.open(Self.releasesPage)
        }
    }
}
