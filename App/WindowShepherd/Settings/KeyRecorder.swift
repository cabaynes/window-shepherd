import AppKit
import WindowShepherdCore

/// Catches the next key press for a recorder box. An event tap sees keys
/// before any app's global shortcut, so pressing a shortcut another app owns
/// records it instead of running it. The tap's callback only captures the key
/// and swallows it; everything else happens on the next main-loop turn
/// (macOS switches off a tap whose callback runs long). Falls back to a
/// local key monitor if the tap can't be created.
@MainActor
final class KeyRecorder {
    var onKey: ((UInt16, CGEventFlags) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?

    var isRunning: Bool { tap != nil || localMonitor != nil }

    func start() {
        guard !isRunning else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                       eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let rec = Unmanaged<KeyRecorder>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { MainActor.assumeIsolated { rec.reenable() } }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            DispatchQueue.main.async { MainActor.assumeIsolated { rec.onKey?(code, flags) } }
            return nil   // swallow it
        }, userInfo: me) {
            self.tap = tap
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            Log.info("recorder: couldn't create an event tap; listening in this window only")
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                self?.onKey?(e.keyCode, CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue)))
                return nil
            }
        }
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        localMonitor = nil
    }
}
