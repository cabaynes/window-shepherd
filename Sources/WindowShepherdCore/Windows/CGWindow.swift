import CoreGraphics
import Foundation

/// One entry of macOS's on-screen window list. Reading the list takes a few
/// hundredths of a second and never talks to apps, so the menu, the snapshot
/// and the front-window lookups all use it (lesson #1 of the Hammerspoon
/// version: never ask every app for its windows).
public struct CGWindow: Equatable {
    public let id: UInt32
    public let pid: pid_t
    public let app: String
    public let title: String?
    public let frame: CGRect

    public init(id: UInt32, pid: pid_t, app: String, title: String?, frame: CGRect) {
        self.id = id; self.pid = pid; self.app = app; self.title = title; self.frame = frame
    }

    /// Normal app windows visible right now (layer 0, on screen, both sides
    /// over 80 pt), front to back. `excludingPID` drops our own windows; the
    /// lock screen (loginwindow) is never one.
    public static func parse(_ list: [[String: Any]], excludingPID: pid_t?) -> [CGWindow] {
        list.compactMap { w in
            let owner = w[kCGWindowOwnerName as String] as? String
            guard (w[kCGWindowLayer as String] as? Int) == 0, owner != "loginwindow",
                  (w[kCGWindowIsOnscreen as String] as? Bool) == true,
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != excludingPID,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
                  rect.width > 80, rect.height > 80 else { return nil }
            return CGWindow(id: id, pid: pid, app: owner ?? "?",
                            title: w[kCGWindowName as String] as? String, frame: rect)
        }
    }

    /// Ids of every normal (layer 0) window that exists, on screen or not.
    public static func allIDs(excludingPID: pid_t? = getpid()) -> Set<UInt32> {
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        var ids = Set<UInt32>()
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != excludingPID else { continue }
            ids.insert(id)
        }
        return ids
    }

    public static func current(excludingPID: pid_t? = getpid()) -> [CGWindow] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return parse(list, excludingPID: excludingPID)
    }
}
