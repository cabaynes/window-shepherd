// Developer tool: inspect screens and windows, move a window, and check where
// a window is (used by scripts/e2e.sh). `move` needs a terminal with the
// Accessibility permission; the rest only read macOS's window list.
import AppKit
import WindowShepherdCore

let system = LiveWindowSystem()
let args = Array(CommandLine.arguments.dropFirst())

func fmt(_ r: CGRect) -> String { String(format: "%.0f %.0f %.0f %.0f", r.minX, r.minY, r.width, r.height) }

func usage() -> Never {
    print("usage: wsctl screens | windows | move <id> <x> <y> <w> <h> | check <title> <n|own> <x y w h|center>")
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
case "move":
    guard args.count == 6, let id = UInt32(args[1]), let x = Double(args[2]), let y = Double(args[3]),
          let w = Double(args[4]), let h = Double(args[5]) else { usage() }
    guard let win = handle(for: id) else { print("no window \(id)"); exit(1) }
    do { try win.setFrame(CGRect(x: x, y: y, width: w, height: h)); print("moved") }
    catch { print("failed: \(error)"); exit(1) }
case "check":
    // check <title> <screen|own> <x> <y> <w> <h>  — is the window at that unit rect? (±3 pt)
    // check <title> <screen|own> center            — centred on that screen?
    guard args.count == 7 || args.count == 4 else { usage() }
    guard let w = system.visibleWindows().first(where: { $0.title == args[1] }) else { print("FAIL \(args[1]): not on screen"); exit(1) }
    let screens = system.screens()
    let dests = Screens.destinations(screens)
    let target: ScreenInfo? = args[2] == "own" ? Geometry.screen(mostOf: w.frame, in: screens) : Int(args[2]).flatMap { $0 <= dests.count ? dests[$0 - 1].screen : nil }
    guard let s = target else { print("FAIL \(args[1]): no screen \(args[2])"); exit(1) }
    let want: CGRect
    if args[3] == "center" {
        want = Geometry.centered(w.frame.size, in: s.frame)
    } else {
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
