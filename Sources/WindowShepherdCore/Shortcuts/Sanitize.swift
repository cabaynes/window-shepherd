import Foundation

/// A saved config made safe: every well-formed entry kept, every damaged or
/// clashing one put back to its default. `notes` say what was reset (for the
/// log). `saved` is untyped JSON on purpose, so one damaged value costs only
/// its own entry. `isValidKey` (optional) is false for a key this keyboard
/// can't bind (a layout switch since it was recorded).
public func sanitize(saved: Any?, isValidKey: ((String) -> Bool)? = nil) -> (ShortcutConfig, [String]) {
    var cfg = ShortcutConfig.defaults
    var notes: [String] = []
    guard let saved = saved as? [String: Any] else { return (cfg, notes) }

    for (id, value) in (saved["actions"] as? [String: Any]) ?? [:] {
        guard let action = ActionID(rawValue: id) else {
            notes.append("unknown action “\(id)” ignored")
            continue
        }
        guard let c = wellFormedCombo(value) else {
            notes.append("saved shortcut for \(id) was damaged; using the default")
            continue
        }
        if let isValidKey, !isValidKey(c.key) {
            notes.append("saved shortcut for \(id) uses a key this keyboard doesn't have; using the default")
            continue
        }
        cfg.actions[action] = c
    }
    for (name, entry) in [("wholeApp", Entry.wholeApp), ("nextScreen", Entry.nextScreen)] {
        guard let raw = saved[name] else { continue }
        if let s = raw as? String, let m = Mod(rawValue: s) {
            cfg[entry] = .mod(m)
        } else {
            notes.append("saved “\(name)” was damaged; using the default")
        }
    }
    if let raw = saved["screenBase"] {
        if let mods = wellFormedMods(raw) {
            cfg.screenBase = mods
        } else {
            notes.append("saved screen keys were damaged; using the default")
        }
    }
    if let raw = saved["menu"] {
        if let c = wellFormedCombo(raw), isValidKey?(c.key) ?? true {
            cfg.menu = c
        } else {
            notes.append("saved menu shortcut was damaged; using the default")
        }
    }

    // Reset clashing entries one problem at a time until the config is valid.
    let defaults = ShortcutConfig.defaults
    for _ in 0..<30 {
        let problems = validate(cfg)
        if problems.isEmpty { return (cfg, notes) }
        var reset = false
        for p in problems {
            for e in p.entries where cfg[e] != defaults[e] {
                cfg[e] = defaults[e]
                let name = e.key.hasPrefix("action:") ? String(e.key.dropFirst("action:".count)) : e.key
                notes.append("“\(name)” clashed (\(p.why)); using the default")
                reset = true
            }
            if reset { break }
        }
        if !reset { break }
    }
    if validate(cfg).isEmpty { return (cfg, notes) }
    notes.append("saved shortcuts couldn't be repaired; using all defaults")
    return (.defaults, notes)
}

private func wellFormedMods(_ raw: Any) -> Set<Mod>? {
    guard let list = raw as? [Any] else { return nil }
    var mods = Set<Mod>()
    for x in list {
        guard let s = x as? String, let m = Mod(rawValue: s) else { return nil }
        mods.insert(m)
    }
    return mods
}

private func wellFormedCombo(_ raw: Any) -> Combo? {
    guard let d = raw as? [String: Any], let key = d["key"] as? String, !key.isEmpty,
          let rawMods = d["mods"], let mods = wellFormedMods(rawMods) else { return nil }
    return Combo(mods: mods, key: key)
}

public extension ShortcutConfig {
    /// The JSON object `sanitize` reads (and the app saves).
    var jsonObject: [String: Any] {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
