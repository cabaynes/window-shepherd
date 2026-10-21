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

/// The list beside each box is set a size smaller, so a row stays short.
private let listFont = Font.system(size: 11)
private let modSymbols: Set<Character> = ["⌃", "⌥", "⌘", "⇧"]

/// One clash to list: the shortcut and what it clashes with.
private struct Clash: Hashable {
    let keys: String
    let text: String
    let level: Finding.Level
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var height: CGFloat = 780
    private var flow: SettingsFlow { model.flow }

    var body: some View {
        let vm = model.vm
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Move the window you're using",
                            intro: "Each shortcut moves the window you're using. The list beside it is the same move "
                                 + "with one extra key (set under Extra keys): for every window of that app, onto the "
                                 + "next screen, or both.") {
                        rows(vm.rows.filter { $0.section == "This window" })
                    }
                    section("Corners") { rows(vm.rows.filter { $0.section == "Corners" }) }
                    section("Extra keys", intro: "Hold one more key with any shortcut above.") {
                        modifierRow(name: "Every window of the app", entry: .wholeApp,
                                    note: example(vm, .wholeApp),
                                    isOn: { $0 == vm.wholeApp }) { flow.setModifier(.wholeApp, $0) }
                        Divider()
                        modifierRow(name: "On the next screen", entry: .nextScreen, note: example(vm, .nextScreen),
                                    isOn: { $0 == vm.nextScreen }) { flow.setModifier(.nextScreen, $0) }
                    }
                    section("Send to a screen",
                            intro: "Press these keys plus a screen's number: 1 is the laptop, then monitors from left to right.") {
                        modifierRow(name: "Keys for screen n", entry: .screenBase, note: nil, list: vm.screenChips,
                                    isOn: { vm.screenBase.contains($0) }) { flow.toggleScreenMod($0) }
                    }
                    section("Open the menu") { rows([vm.menu]) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            Divider()
            HStack {
                Text(flow.statusText)
                    .font(.callout)
                    .foregroundStyle(.primary)
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
        .frame(width: 680, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, intro: String? = nil,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 18)
            if let intro {
                Text(intro)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
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
        let deciding = pendingChoice(r.entry)
        // The menu row has no list: its one shortcut is the whole story.
        let list = r.chips.isEmpty ? [] : [ChipVM(label: "This window", keys: r.keys, level: r.level, text: r.text)] + r.chips
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(r.name).fontWeight(.medium).frame(width: 150, alignment: .leading).padding(.top, 4)
                recorderBox(r)
                resetButton(r).padding(.top, 4)
                if deciding {
                    // Right beside the box, so the choice is where your eyes are.
                    choiceButtons
                } else if !list.isEmpty {
                    variantList(list, base: r.keys).padding(.leading, 12)
                }
                Spacer(minLength: 0)
            }
            messages(entry: r.entry, clashes: deciding ? [] : clashes(list.isEmpty ? [ChipVM(label: "", keys: r.keys, level: r.level, text: r.text)] : list))
        }
        .padding(.vertical, 8)
    }

    private func resetButton(_ r: RowVM) -> some View {
        Button { flow.reset(r.entry) } label: { Text("↺").font(.system(size: 15)) }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .help("Back to the default")
            .opacity(r.isDefault ? 0 : 1)
            .disabled(r.isDefault)
            .frame(width: 20)
    }

    private func recorderBox(_ r: RowVM) -> some View {
        let recording = flow.recording == r.entry
        let error = flow.errors[r.entry.key] != nil
        let border: Color = recording ? .accentColor : (error || r.level == .block) ? Palette.red
            : r.level == .warn ? Palette.amber : Color(nsColor: .separatorColor)
        return Button {
            if recording { flow.stopRecording() } else { flow.record(r.entry) }
        } label: {
            Text(recording ? (flow.recordHint ?? "Press keys… (Esc to cancel)") : (pendingKeys(r.entry) ?? r.keys))
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

    /// "This window ⌥⌘←" then each extra-key version, the added keys drawn in
    /// the accent colour so you can see what each line adds.
    private func variantList(_ list: [ChipVM], base: String) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
            ForEach(list, id: \.label) { c in
                GridRow {
                    Text(c.label).foregroundStyle(.primary).fixedSize()
                    // ⚠ in its own column, so every shortcut starts at the same place.
                    Text(c.level != nil ? "⚠" : "").foregroundStyle(color(c.level) ?? .primary)
                    if let keys = c.keys {
                        keysText(keys, base: c.label == "This window" ? keys : base, level: c.level)
                            .fixedSize()
                            .help(c.text ?? "")
                    } else {
                        Text("Menu only").foregroundStyle(.primary).fixedSize()
                            .help("This shortcut already uses that extra key, so this version is only in the ⧉ menu.")
                    }
                }
            }
        }
        .font(listFont)
    }

    private func keysText(_ keys: String, base: String, level: Finding.Level?) -> Text {
        let baseMods = Set(base.filter { modSymbols.contains($0) })
        let plain = color(level) ?? .primary
        return keys.reduce(Text("")) { out, ch in
            let added = modSymbols.contains(ch) && !baseMods.contains(ch)
            return out + Text(String(ch)).foregroundColor(added ? .accentColor : plain).fontWeight(added ? .bold : .regular)
        }
    }

    // MARK: Clashes

    private func clashes(_ list: [ChipVM]) -> [Clash] {
        list.compactMap { c in
            guard let keys = c.keys, let level = c.level, let text = c.text else { return nil }
            return Clash(keys: keys, text: text, level: level)
        }
    }

    private func pendingChoice(_ entry: Entry) -> Bool {
        guard let p = flow.pending, p.entry == entry, flow.errors[entry.key] == nil else { return false }
        return !p.waiting
    }

    private func pendingKeys(_ entry: Entry) -> String? {
        guard let p = flow.pending, p.entry == entry else { return nil }
        return p.keys
    }

    private var choiceButtons: some View {
        HStack(spacing: 8) {
            Button("Save anyway") { flow.keep() }.keyboardShortcut(.defaultAction)
            Button("Cancel") { flow.cancel() }.keyboardShortcut(.cancelAction)
        }
        .padding(.leading, 12)
    }

    @ViewBuilder
    private func messages(entry: Entry, clashes: [Clash]) -> some View {
        if let err = flow.errors[entry.key] {
            message(err, level: .block)
        } else if let p = flow.pending, p.entry == entry {
            if p.waiting {
                message("Checking your open apps… \(p.keys ?? "") will be set when that's done (keep this window open).", level: .warn)
            } else {
                // Judge writes each as "⌘C — Safari: Copy. Yours will win."
                clashBox(p.warns.map { w in
                    let parts = w.components(separatedBy: " — ")
                    return Clash(keys: parts.count > 1 ? parts[0] : "", text: parts.dropFirst().joined(separator: " — "), level: .warn)
                })
            }
        } else if !clashes.isEmpty {
            clashBox(clashes)
        }
    }

    private func clashBox(_ list: [Clash]) -> some View {
        let blocked = list.contains { $0.level == .block }
        // "Yours will win." ends every app clash: say it once, in the heading.
        let wins = " Yours will win."
        let anyWins = list.contains { $0.text.hasSuffix(wins) }
        let title = (list.count == 1 ? "Potential conflict" : "Potential conflicts") + (anyWins ? " (Window Shepherd wins)" : "")
        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(blocked ? Palette.red : Palette.amber)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 2) {
                ForEach(list, id: \.self) { c in
                    GridRow {
                        Text(c.keys).fontWeight(.medium)
                        Text(c.text.hasSuffix(wins) ? String(c.text.dropLast(wins.count)) : c.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(c.level == .block ? Palette.red : Palette.amber)
                }
            }
        }
        .font(listFont)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(blocked ? Palette.redBG : Palette.amberBG))
        .padding(.leading, 160)
    }

    private func message(_ text: String, level: Finding.Level) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(level == .block ? Palette.red : Palette.amber)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(level == .block ? Palette.redBG : Palette.amberBG))
    }

    // MARK: Extra keys and screens

    /// A worked example from your own Left half keys, so it stays true after you change them.
    private func example(_ vm: SettingsVM, _ entry: Entry) -> String? {
        guard let left = vm.rows.first(where: { $0.entry == .action(.leftHalf) }) else { return nil }
        switch entry {
        case .wholeApp:
            guard let all = left.chips.first(where: { $0.label == "Every window of the app" })?.keys else { return nil }
            return "\(left.keys) puts the window you're using on the left half; \(all) does that to all of that app's windows."
        case .nextScreen:
            guard let next = left.chips.first(where: { $0.label == "On the next screen" })?.keys else { return nil }
            return "\(next) puts the window you're using on the left half of the next screen."
        default:
            return nil
        }
    }

    private func modifierRow(name: String, entry: Entry, note: String?, list: [ChipVM] = [],
                             isOn: @escaping (Mod) -> Bool, tap: @escaping (Mod) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(name).fontWeight(.medium).frame(width: 150, alignment: .leading).padding(.top, 4)
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
                if !list.isEmpty {
                    variantList(list, base: list.first?.keys ?? "").padding(.leading, 12)
                }
                Spacer(minLength: 0)
            }
            if let note {
                Text(note).font(listFont).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 160)
            }
            messages(entry: entry, clashes: clashes(list))
        }
        .padding(.vertical, 8)
    }
}
