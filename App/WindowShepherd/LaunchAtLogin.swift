import ServiceManagement
import WindowShepherdCore

/// Start at login, via the system's login-item list (no helper app).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Log.info("launch at login " + (on ? "on" : "off"))
        } catch {
            Log.info("couldn't change launch at login: \(error.localizedDescription)")
            HUD.show("Couldn't change Launch at Login")
        }
    }
}
