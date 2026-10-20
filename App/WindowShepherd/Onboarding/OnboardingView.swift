import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var granted = false
    @Published var launchAtLogin = true
    var onDone: (() -> Void)?
}

/// First run: why the permission is needed, a button to the right pane of
/// System Settings, and "You're all set" the moment it's granted.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("⧉").font(.system(size: 40))
                Text(model.granted ? "You're all set" : "Window Shepherd needs one permission")
                    .font(.title2.weight(.semibold))
            }
            if model.granted {
                Text("Window Shepherd is in your menu bar (⧉). Open the ⧉ menu to see everything it can do, and the keyboard shortcut for each (⌥⌘G makes the window in front 90%, for example).")
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Start Window Shepherd at login", isOn: $model.launchAtLogin)
                HStack {
                    Spacer()
                    Button("Done") { model.onDone?() }.keyboardShortcut(.defaultAction)
                }
            } else {
                Text("To move and resize windows, macOS asks you to allow Window Shepherd under Accessibility. It only moves windows; it never reads what's in them, and it makes no network connections except checking for updates.")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Click Open Accessibility Settings below.")
                    step(2, "Turn on Window Shepherd in the list. If it isn't there, click + and choose Window Shepherd from Applications.")
                    step(3, "Come back here. This window notices by itself.")
                }
                HStack {
                    Spacer()
                    Button("Open Accessibility Settings") { PermissionWatcher.openSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(24)
        .frame(width: 480)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").fontWeight(.semibold).frame(width: 18, alignment: .trailing)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
