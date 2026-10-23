// Developer tool: inspect screens and windows, move a window, and check where
// a window is (used by scripts/e2e.sh). `move` needs a terminal with the
// Accessibility permission; the rest only read macOS's window list.
import AppKit
import WindowShepherdCore

let system = LiveWindowSystem()
let args = Array(CommandLine.arguments.dropFirst())

func fmt(_ r: CGRect) -> String { String(format: "%.0f %.0f %.0f %.0f", r.minX, r.minY, r.width, r.height) }

func usage() -> Never {
    print("usage: wsctl screens | windows | front [seconds] | move <id> <x> <y> <w> <h> | scan | check <id|title> <n|own> <x y w h|center|default>")
    exit(2)
}

func handle(for id: UInt32) -> WindowHandle? {
    guard let w = system.visibleWindows().first(where: { $0.id == id }) else { return nil }
    return (try? system.appWindows(pid: w.pid))?.first { $0.windowID == id }
}

switch args.first {
case "screens":
    for d in Screens.destinations(system.screens()) {
        print("\(d.num)\t\(d.name)\t\(d.screen.uuid)\tframe \(fmt(d.screen.frame))\tfull \(fmt(d.screen.full))")
    }
case "windows":
    for w in system.visibleWindows() {
        print("\(w.id)\t\(w.pid)\t\(w.app)\t\(w.title ?? "")\t\(fmt(w.frame))")
    }
case "front":   // after a pause, so you can switch to the app first
    Thread.sleep(forTimeInterval: Double(args.dropFirst().first ?? "") ?? 5)
    guard let pid = system.frontmostPID() else { print("no front app"); exit(1) }
    let app = system.appName(pid: pid) ?? "?"
    let mine = system.visibleWindows().filter { $0.pid == pid }
    print("front app: \(app)")
    for (i, w) in mine.enumerated() { print("  on-screen order \(i + 1): window \(w.id)  \(fmt(w.frame))") }
    if let f = system.focusedWindow(pid: pid) {
        print("  keyboard focus (needs Accessibility): window \(f.windowID.map(String.init) ?? "?")  \(f.frame().map(fmt) ?? "?")")
    } else {
        print("  keyboard focus: not readable (give this terminal Accessibility)")
    }
case "move":
    guard args.count == 6, let id = UInt32(args[1]), let x = Double(args[2]), let y = Double(args[3]),
          let w = Double(args[4]), let h = Double(args[5]) else { usage() }
    guard let win = handle(for: id) else { print("no window \(id)"); exit(1) }
    do { try win.setFrame(CGRect(x: x, y: y, width: w, height: h)); print("moved") }
    catch { print("failed: \(error)"); exit(1) }
case "scan":
    // Runs the Customize Shortcuts clash scan and prints what it found.
    let t0 = Date()
    let combos = derive(.defaults).map(\.combo)
    MainActor.assumeIsolated {
        _ = ClashScanner().start(combos: combos, onUpdate: { _, done, total in
            if done == 0 { print("scanning \(total) apps…") }
        }, onDone: { sources in
            print("system clashes with the defaults: \(sources.system.map { "\($0.combo.formatted) \($0.name)" })")
            print("app shortcuts known: \(sources.apps.count)")
            print(String(format: "took %.2fs", Date().timeIntervalSince(t0)))
            exit(0)
        })
    }
    RunLoop.main.run()
case "check":
    // check <window id|title> <screen n|own> <x> <y> <w> <h>   — at that unit rect? (±3 pt)
    // check <window id|title> <screen n|own> center|default    — centred / at screen n's default size
    guard args.count == 7 || (args.count == 4 && ["center", "default"].contains(args[3])) else { usage() }
    let match: (CGWindow) -> Bool = UInt32(args[1]).map { id in { $0.id == id } } ?? { $0.title == args[1] }
    guard let w = system.visibleWindows().first(where: match) else { print("not on screen"); exit(1) }
    let screens = system.screens()
    let dests = Screens.destinations(screens)
    let dest: Destination? = Int(args[2]).flatMap { $0 >= 1 && $0 <= dests.count ? dests[$0 - 1] : nil }
    guard let s = args[2] == "own" ? Geometry.screen(mostOf: w.frame, in: screens) : dest?.screen else {
        print("no screen \(args[2])"); exit(1)
    }
    let want: CGRect
    switch args[3] {
    case "center": want = Geometry.centered(w.frame.size, in: s.frame)
    case "default":
        guard let d = dest ?? dests.first(where: { $0.screen == s }) else { print("no screen"); exit(1) }
        want = Placer.fraction(Screens.defaultFraction(d), on: .own).frame(for: .zero, screens: [s], main: s)!
    default:
        guard let x = Double(args[3]), let y = Double(args[4]), let ww = Double(args[5]), let hh = Double(args[6]) else { usage() }
        want = Geometry.place(UnitRect(x: x, y: y, w: ww, h: hh), in: s.frame)
    }
    let ok = abs(w.frame.minX - want.minX) <= 3 && abs(w.frame.minY - want.minY) <= 3
        && abs(w.frame.width - want.width) <= 3 && abs(w.frame.height - want.height) <= 3
    print(ok ? "ok" : "got \(fmt(w.frame)), want \(fmt(want))")
    exit(ok ? 0 : 1)
default:
    usage()
}
