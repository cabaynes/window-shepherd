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

/// Saved shortcuts this keyboard can't bind (`action:<name>` and `menu`), exactly as saved.
/// `sanitize` puts their defaults in use; `encodeForSave` writes these back, so a key is
/// never lost just because a different keyboard layout was on when you saved.
public func unbindableSaved(saved: Any?, isValidKey: (String) -> Bool) -> [String: Any] {
    guard let saved = saved as? [String: Any] else { return [:] }
    var held: [String: Any] = [:]
    for (id, value) in (saved["actions"] as? [String: Any]) ?? [:] {
        guard ActionID(rawValue: id) != nil, let c = wellFormedCombo(value), !isValidKey(c.key) else { continue }
        held["action:" + id] = value
    }
    if let raw = saved["menu"], let c = wellFormedCombo(raw), !isValidKey(c.key) { held["menu"] = raw }
    return held
}

/// The JSON to store for `cfg`, with each held entry (`unbindableSaved`) whose shortcut you
/// left at its default written back as it was. nil: all defaults and nothing held (store nothing).
public func encodeForSave(_ cfg: ShortcutConfig, keeping held: [String: Any]) -> Data? {
    let defaults = ShortcutConfig.defaults
    var keep: [String: Any] = [:]
    for (k, v) in held {
        if k == "menu" {
            if cfg.menu == defaults.menu { keep[k] = v }
        } else if let a = ActionID(rawValue: String(k.dropFirst("action:".count))), cfg.actions[a] == defaults.actions[a] {
            keep[k] = v
        }
    }
    if cfg.isDefault && keep.isEmpty { return nil }
    guard let data = try? JSONEncoder().encode(cfg),
          var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    var actions = obj["actions"] as? [String: Any] ?? [:]
    for (k, v) in keep {
        if k == "menu" { obj["menu"] = v } else { actions[String(k.dropFirst("action:".count))] = v }
    }
    obj["actions"] = actions
    return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
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
