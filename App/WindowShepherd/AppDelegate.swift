import AppKit
import WindowShepherdCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Window Shepherd \(Bundle.main.shortVersion) started")
        statusMenu = StatusMenuController()
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
}
