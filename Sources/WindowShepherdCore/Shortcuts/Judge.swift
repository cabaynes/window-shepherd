import Foundation

/// What a proposed change means: blocked (with the reason), warnings to
/// confirm with Keep / Cancel, or fine.
public enum Verdict: Equatable {
    case ok, blocked(String), warn([String])
}

func touches(_ b: ShortcutBinding, _ entry: Entry?) -> Bool {
    guard let entry else { return true }
    return b.entries.contains(entry)
}

/// Findings for every binding of `cfg`, with a live macOS check for its
/// combos (new candidates the scan never saw).
func findings(for cfg: ShortcutConfig, sources: ClashSources,
              systemCheck: ([Combo]) -> [SystemShortcut]) -> ([String: [Finding]], [ShortcutBinding]) {
    let bindings = derive(cfg)
    let combos = bindings.map(\.combo)
    let merged = ClashSources(system: systemCheck(combos), apps: sources.apps)
    return (Conflicts.check(bindings: combos, sources: merged), bindings)
}

/// Judge a candidate config for a change to `entry` (nil = reset all).
/// Clashes with Window Shepherd itself, or a macOS shortcut that would take
/// the key first, block; app shortcuts ask first.
public func judge(candidate: ShortcutConfig, entry: Entry?, sources: ClashSources,
                  systemCheck: ([Combo]) -> [SystemShortcut]) -> Verdict {
    let problems = validate(candidate)
    if let first = problems.first {
        for p in problems where entry == nil || p.entries.contains(entry!) { return .blocked(p.why) }
        return .blocked(first.why)
    }
    let (found, bindings) = findings(for: candidate, sources: sources, systemCheck: systemCheck)
    var warns: [String] = []
    for b in bindings where touches(b, entry) {
        for f in found[b.combo.id] ?? [] {
            if f.level == .block { return .blocked(b.combo.formatted + ": " + f.text) }
            warns.append(b.combo.formatted + " — " + f.text)
        }
    }
    return warns.isEmpty ? .ok : .warn(warns)
}
