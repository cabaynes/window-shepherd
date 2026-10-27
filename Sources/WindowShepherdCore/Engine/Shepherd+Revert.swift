import Foundation

/// What the Revert row offers: the combination, when its frozen copy was
/// taken, and how many windows on screen aren't where they were then.
public struct RevertInfo: Equatable {
    public let label: String
    public let at: Date
    public let notWhere: Int

    public init(label: String, at: Date, notWhere: Int) { self.label = label; self.at = at; self.notWhere = notWhere }
}

/// The frozen-copy side of auto-restore: the flashing icon when a restore
/// leaves windows behind, and Revert, which puts the frozen copy back.
extension Shepherd {
    func setFlashing(_ on: Bool) {
        guard on != flashing else { return }
        flashing = on
        onFlashChanged?(on)
    }

    /// The menu opened: you've seen it, stop flashing (nothing is resolved).
    public func menuOpened() { setFlashing(false) }

    /// The Revert row for the screens connected now, or nil: no screen change
    /// into them yet, or nothing frozen for them. Cheap (fast window list).
    public func revertInfo() -> RevertInfo? {
        let screens = system.screens()
        let key = Screens.setupKey(screens)
        guard lastChange?.key == key, let copy = book.frozen[key] else { return nil }
        var notWhere = 0
        for w in system.visibleWindows() {
            guard let e = copy.layout[String(w.id)] else { continue }
            if !Geometry.sameSpot(Geometry.whereIs(w.frame, in: screens), e.spot) { notWhere += 1 }
        }
        return RevertInfo(label: Screens.setupLabel(screens), at: Date(timeIntervalSince1970: copy.at), notWhere: notWhere)
    }

    /// Put every window in the frozen copy back where it was, replacing any
    /// restore still running (quietly), with the full patience.
    public func revert() {
        let key = Screens.setupKey(system.screens())
        guard let copy = book.frozen[key] else { return }
        cancelRestores()
        if runner.current?.kind == .restore { runner.stopCurrent(reportAs: nil) }
        resumeRestore = false
        book.layouts[key, default: [:]].merge(copy.layout) { _, frozen in frozen }
        for id in copy.layout.keys { book.protect[id] = nil }
        Log.info("revert \(Screens.setupLabel(system.screens())) to its frozen copy (\(copy.layout.count) windows)")
        book.restoredIds = []
        restore(patience: restoreTiming.patience)
        updateBusy()
    }
}
