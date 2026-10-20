import SwiftUI
import WindowShepherdCore

/// Colours from the Hammerspoon prototype's settings page, light and dark.
private enum Palette {
    static let red = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 1, green: 0.42, blue: 0.42, alpha: 1)
                                                                    : NSColor(srgbRed: 0.78, green: 0.16, blue: 0.16, alpha: 1) })
    static let redBG = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.23, green: 0.12, blue: 0.12, alpha: 1)
                                                                      : NSColor(srgbRed: 0.99, green: 0.93, blue: 0.92, alpha: 1) })
    static let amber = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 1, green: 0.77, blue: 0.34, alpha: 1)
                                                                      : NSColor(srgbRed: 0.54, green: 0.33, blue: 0, alpha: 1) })
    static let amberBG = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.23, green: 0.18, blue: 0.09, alpha: 1)
                                                                        : NSColor(srgbRed: 1, green: 0.96, blue: 0.86, alpha: 1) })
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

private func color(_ level: Finding.Level?) -> Color? {
    switch level {
    case .block?: return Palette.red
    case .warn?: return Palette.amber
    case nil: return nil
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    private var flow: SettingsFlow { model.flow }

    var body: some View {
        let vm = model.vm
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("This window") { rows(vm.rows.filter { $0.section == "This window" }) }
                    section("Corners") { rows(vm.rows.filter { $0.section == "Corners" }) }
                    section("Add a key") {
                        modifierRow(name: "Every window of the app", entry: .wholeApp,
                                    note: "added to each shortcut above that doesn't already have it",
                                    isOn: { $0 == vm.wholeApp }) { flow.setModifier(.wholeApp, $0) }
                        Divider()
                        modifierRow(name: "On the next screen", entry: .nextScreen, note: nil,
                                    isOn: { $0 == vm.nextScreen }) { flow.setModifier(.nextScreen, $0) }
                    }
                    section("Screens (1 = laptop, then monitors left to right)") {
                        modifierRow(name: "Move to screen n", entry: .screenBase, note: nil, chips: vm.screenChips,
                                    isOn: { vm.screenBase.contains($0) }) { flow.toggleScreenMod($0) }
                    }
                    section("Menu") { rows([vm.menu]) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            Divider()
            HStack {
                Text(flow.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset all") { flow.resetAll() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            if let err = flow.errors[SettingsFlow.allKey] {
                message(err, level: .block).padding(.horizontal, 20).padding(.bottom, 8)
            }
            HStack(spacing: 4) {
                Text("Window Shepherd is free. If it saves you time, you can")
                Link("buy me a coffee ☕", destination: URL(string: "https://buymeacoffee.com/cccccccharles")!)
            }
            .font(.callout)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        }
    }

    @ViewBuilder
    private func rows(_ list: [RowVM]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.entry.key) { i, r in
            if i > 0 { Divider() }
            row(r)
        }
    }

    private func row(_ r: RowVM) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(r.name).fontWeight(.medium).frame(width: 150, alignment: .leading)
                recorderBox(r)
                Button { flow.reset(r.entry) } label: { Text("↺").font(.system(size: 15)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Back to the default")
                    .opacity(r.isDefault ? 0 : 1)
                    .disabled(r.isDefault)
                    .frame(width: 20)
                chips(r.chips)
                Spacer(minLength: 0)
            }
            messages(entry: r.entry, level: r.level, text: r.text)
        }
        .padding(.vertical, 8)
    }

    private func recorderBox(_ r: RowVM) -> some View {
        let recording = flow.recording == r.entry
        let error = flow.errors[r.entry.key] != nil
        let border: Color = recording ? .accentColor : (error || r.level == .block) ? Palette.red
            : r.level == .warn ? Palette.amber : Color(nsColor: .separatorColor)
        return Button {
            if recording { flow.stopRecording() } else { flow.record(r.entry) }
        } label: {
            Text(recording ? (flow.recordHint ?? "Press keys… (Esc to cancel)") : r.keys)
                .font(.system(size: recording ? 12 : 14))
                .foregroundStyle(.primary)
                .frame(width: 120, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: recording ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(r.text ?? "Click, then press the new shortcut")
    }

    private func chips(_ list: [ChipVM]) -> some View {
        HStack(spacing: 6) {
            ForEach(list, id: \.label) { c in
                Group {
                    if let keys = c.keys {
                        HStack(spacing: 4) {
                            if c.level != nil { Text("⚠") }
                            Text(keys)
                            Text(c.label).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(c.label + ":").font(.caption).foregroundStyle(.secondary)
                            Text("menu only")
                        }
                    }
                }
                .foregroundStyle(color(c.level) ?? .primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(
                    c.level == .block ? Palette.redBG : c.level == .warn ? Palette.amberBG : Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
                .help(c.text ?? "")
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func messages(entry: Entry, level: Finding.Level?, text: String?) -> some View {
        if let err = flow.errors[entry.key] {
            message(err, level: .block)
        } else if let p = flow.pending, p.entry == entry {
            if p.waiting {
                message("Checking your open apps… \(p.keys ?? "") will be set when that's done.", level: .warn)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(p.warns, id: \.self) { Text($0) }
                    HStack {
                        Button("Keep \(p.keys ?? "it")") { flow.keep() }.keyboardShortcut(.defaultAction)
                        Button("Cancel") { flow.cancel() }
                    }
                }
                .font(.callout)
                .foregroundStyle(Palette.amber)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.amberBG))
            }
        } else if let level, let text {
            message(text, level: level)
        }
    }

    private func message(_ text: String, level: Finding.Level) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(level == .block ? Palette.red : Palette.amber)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(level == .block ? Palette.redBG : Palette.amberBG))
    }

    private func modifierRow(name: String, entry: Entry, note: String?, chips list: [ChipVM] = [],
                             isOn: @escaping (Mod) -> Bool, tap: @escaping (Mod) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(name).fontWeight(.medium).frame(width: 150, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(Mod.allCases, id: \.self) { m in
                        Button { tap(m) } label: {
                            Text(m.symbol)
                                .font(.system(size: 15))
                                .frame(width: 32, height: 26)
                                .foregroundStyle(isOn(m) ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 6).fill(isOn(m) ? Color.accentColor
                                                                                           : Color(nsColor: .textBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn(m) ? Color.accentColor
                                                                                           : Color(nsColor: .separatorColor)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
                chips(list)
                Spacer(minLength: 0)
            }
            messages(entry: entry, level: nil, text: nil)
        }
        .padding(.vertical, 8)
    }
}
