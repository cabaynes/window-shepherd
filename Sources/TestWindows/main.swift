// Opens titled test windows so integration checks can move something other
// than real work windows.  Usage: TestWindows <n> [--title-prefix P]
import AppKit

let args = CommandLine.arguments
let count = args.count > 1 ? Int(args[1]) ?? 2 : 2
var prefix = "WSTEST"
if let i = args.firstIndex(of: "--title-prefix"), i + 1 < args.count { prefix = args[i + 1] }

let app = NSApplication.shared
app.setActivationPolicy(.regular)
var windows: [NSWindow] = []
let origin = NSScreen.main?.visibleFrame.origin ?? .zero
for n in 1...max(1, count) {
    let w = NSWindow(contentRect: NSRect(x: origin.x + CGFloat(60 + 40 * n), y: origin.y + CGFloat(60 + 30 * n), width: 500, height: 400),
                     styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    w.title = "\(prefix) \(n)"
    w.isReleasedWhenClosed = false
    w.makeKeyAndOrderFront(nil)
    windows.append(w)
}
app.activate()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    // Window numbers are the CoreGraphics window ids (no Screen Recording needed to match them).
    print("ready \(getpid()) " + windows.map { String($0.windowNumber) }.joined(separator: " "))
    fflush(stdout)
}
app.run()
