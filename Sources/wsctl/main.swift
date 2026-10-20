// Developer tool: inspect screens and windows, move a window, and run
// end-to-end scenarios against real windows (run it from a terminal that has
// the Accessibility permission).
import AppKit
import WindowShepherdCore

let system = LiveWindowSystem()
let args = Array(CommandLine.arguments.dropFirst())

func fmt(_ r: CGRect) -> String { String(format: "%.0f %.0f %.0f %.0f", r.minX, r.minY, r.width, r.height) }

func usage() -> Never {
    print("usage: wsctl screens | windows | move <id> <x> <y> <w> <h> | scenario <name>")
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
case "scenario":
    guard args.count >= 2 else { usage() }
    Scenarios.run(args[1])
default:
    usage()
}
