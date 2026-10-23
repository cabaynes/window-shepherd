import ServiceManagement
import WindowShepherdCore

/// Start at login, via the system's login-item list (no helper app).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Whether the user has made (or been offered) the choice yet.
    static var decided: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLoginDecided") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLoginDecided") }
    }

    /// The menu toggle. If macOS is waiting for approval in System Settings, open it there.
    static func toggle() {
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        set(!isEnabled)
    }

    static func set(_ on: Bool) {
        decided = true
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Log.info("launch at login " + (on ? "on" : "off"))
        } catch {
            Log.info("couldn't change launch at login: \(error.localizedDescription)")
            HUD.show("Couldn't change Launch at Login")
        }
    }
}
