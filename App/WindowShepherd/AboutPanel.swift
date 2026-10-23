import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(string: "by Charles Baynes\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: "windowshepherd.com", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: URL(string: "https://windowshepherd.com")!]))
        credits.append(NSAttributedString(string: "\nFree and open source (MIT)", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        credits.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: credits.length))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
