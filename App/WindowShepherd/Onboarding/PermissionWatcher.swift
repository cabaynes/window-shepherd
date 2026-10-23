import AppKit
import ApplicationServices

/// Watches for the Accessibility permission. macOS posts a notification when
/// the list changes; while the onboarding window is open we also check once
/// a second (cheap), since that notification isn't guaranteed.
@MainActor
final class PermissionWatcher {
    private(set) var isTrusted = AXIsProcessTrusted()
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?

    init() {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"),
                                                            object: nil, queue: .main) { [weak self] _ in
            // The new value lands a moment after the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self?.check() } }
        }
    }

    func check() {
        let now = AXIsProcessTrusted()
        guard now != isTrusted else { return }
        isTrusted = now
        onChange?(now)
    }

    func pollWhileVisible(_ on: Bool) {
        timer?.invalidate()
        timer = on ? Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        } : nil
    }

    /// Ask macOS to add Window Shepherd to the Accessibility list (it only
    /// appears there once the app has asked with the prompt option), then open
    /// that pane so it's one switch away.
    static func openSettings() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
