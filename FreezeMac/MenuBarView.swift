import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: FreezeMacModel
    var openMainWindow: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack {
            // 1. Status line
            Text(model.menuStatusText)

            if !model.permissionGranted {
                Button(String(localized: "Grant Permission…")) {
                    model.requestPermission()
                }
            }

            // 2. Start Cleaning
            Button(String(localized: "Start Cleaning")) {
                model.selectPreset(.cleaning)
                model.beginCountdown()
            }
            .disabled(model.phase.isBusy || !model.permissionGranted)

            // 3. Start Freezing
            Button(String(localized: "Start Freezing")) {
                model.selectPreset(.kids)
                model.beginCountdown()
            }
            .disabled(model.phase.isBusy || !model.permissionGranted)

            // 4. Divider
            Divider()

            // 5. Auto-Unlock Time submenu
            Menu(String(localized: "Auto-Unlock Time")) {
                let options: [Int] = model.preset == .kids
                    ? [600, 1200, 1800, 3600]
                    : [30, 60, 120, 300]

                ForEach(options, id: \.self) { seconds in
                    Toggle(durationText(seconds), isOn: Binding(
                        get: { model.settings.autoUnlockSeconds == seconds },
                        set: { if $0 { model.settings.autoUnlockSeconds = seconds } }
                    ))
                }
            }
            .disabled(model.phase.isBusy)

            // 6. Black out displays (hidden in kids mode)
            if model.preset != .kids {
                Toggle(String(localized: "Black out displays"), isOn: $model.blackoutScreen)
                    .disabled(model.phase.isBusy)
            }

            // 7. Divider
            Divider()

            // 8. Open FreezeMac
            Button(String(localized: "Open FreezeMac")) {
                openMainWindow()
            }

            // 9. Settings… (⌘,)
            Button(String(localized: "Settings…")) {
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            // 10. Launch at Login
            Toggle(String(localized: "Launch at Login"), isOn: Binding(
                get: { model.loginItem.isEnabled },
                set: { model.loginItem.setEnabled($0) }
            ))

            // 11. Divider
            Divider()

            // 12. Quit FreezeMac (⌘Q)
            Button(String(localized: "Quit FreezeMac")) {
                model.quitApplication()
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            model.loginItem.refresh()
            model.refreshPermission()
        }
    }
}
