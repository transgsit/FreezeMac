import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: FreezeMacModel

    private enum SettingsTab: Hashable {
        case general, lock, unlock, screen
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            LockSettingsTab(model: model)
                .tabItem {
                    Label("Lock", systemImage: "lock")
                }
                .tag(SettingsTab.lock)

            UnlockSettingsTab(model: model)
                .tabItem {
                    Label("Unlock", systemImage: "lock.open")
                }
                .tag(SettingsTab.unlock)

            ScreenSettingsTab(model: model)
                .tabItem {
                    Label("Screen", systemImage: "display")
                }
                .tag(SettingsTab.screen)
        }
        .frame(width: 520)
        .tint(Frosty.accent)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject var model: FreezeMacModel
    @State private var isRecordingHotKey = false
    @State private var hotKeyMonitor: Any?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.loginItem.isEnabled },
                    set: { model.loginItem.setEnabled($0) }
                ))

                if model.loginItem.requiresApproval {
                    HStack {
                        Text("Approval required in System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") {
                            model.loginItem.openLoginItems()
                        }
                    }
                }

                if let errorMessage = model.loginItem.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Open main window at launch", isOn: $model.preferences.openMainWindowAtLaunch)

                Toggle("Show remaining time in menu bar", isOn: $model.preferences.showRemainingTimeInMenuBar)
            }

            Section {
                Toggle("Use global shortcut", isOn: $model.preferences.hotKeyEnabled)

                if model.preferences.hotKeyEnabled {
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        Button(isRecordingHotKey ? String(localized: "Press shortcut…") : shortcutGlyphs(keyCode: model.preferences.hotKeyCode, modifiers: model.preferences.hotKeyModifiers)) {
                            if isRecordingHotKey {
                                stopRecordingHotKey()
                            } else {
                                startRecordingHotKey()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.hotKey.registrationFailed {
                        Text("This shortcut cannot be used")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.loginItem.refresh()
        }
        .onDisappear {
            stopRecordingHotKey()
        }
    }

    private func startRecordingHotKey() {
        stopRecordingHotKey()
        model.hotKey.unregister()
        isRecordingHotKey = true
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stopRecordingHotKey()
                return nil
            }

            var carbonMods: UInt32 = 0
            if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
            if event.modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }

            let mainModifiers = UInt32(cmdKey | optionKey | controlKey)
            guard (carbonMods & mainModifiers) != 0 else {
                return nil
            }

            let keyCode = Int(event.keyCode)
            model.preferences.hotKeyCode = keyCode
            model.preferences.hotKeyModifiers = carbonMods
            stopRecordingHotKey()
            return nil
        }
    }

    private func stopRecordingHotKey() {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
            self.hotKeyMonitor = nil
        }
        isRecordingHotKey = false
        model.syncHotKey()
    }
}

// MARK: - Lock Tab

private struct LockSettingsTab: View {
    @ObservedObject var model: FreezeMacModel

    var body: some View {
        Form {
            Section {
                Picker("Countdown before locking", selection: $model.preferences.countdownSeconds) {
                    Text("None").tag(0)
                    Text("3 s").tag(3)
                    Text("5 s").tag(5)
                }
            }

            Section {
                Toggle("Lock trackpad and mouse", isOn: $model.lockPointer)
                Toggle("Black out displays", isOn: $model.blackoutScreen)

                if model.blackoutScreen {
                    Text("Screen blackout also locks the trackpad and mouse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Unlock Tab

private struct UnlockSettingsTab: View {
    @ObservedObject var model: FreezeMacModel

    var body: some View {
        Form {
            Section {
                Toggle("Hold a key", isOn: $model.settings.holdKeyEnabled)
                if model.settings.holdKeyEnabled {
                    HStack {
                        Text("Key")
                        Spacer()
                        Button(model.isRecordingUnlockKey ? String(localized: "Press a key…") : KeyCodes.name(for: model.settings.holdKeyCode)) {
                            if model.isRecordingUnlockKey {
                                model.endRecordingUnlockKey()
                            } else {
                                model.beginRecordingUnlockKey()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Stepper(
                        "Hold for \(model.settings.holdKeySeconds) s",
                        value: $model.settings.holdKeySeconds,
                        in: UnlockSettings.holdSecondsRange
                    )
                }
            }

            Section {
                Toggle("Type a word", isOn: $model.settings.wordEnabled)
                if model.settings.wordEnabled {
                    TextField("Word (3–16 letters or digits)", text: $model.settings.word)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    if KeyCodes.codes(for: model.settings.word) == nil {
                        Text("Use only A–Z and 0–9, 3 to 16 characters. Keys are matched by position, so it works while typing Korean too.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section {
                Toggle("Click the trackpad", isOn: $model.settings.clickEnabled)
                    .disabled(!model.lockPointer)

                if model.settings.clickEnabled && model.lockPointer {
                    Stepper(
                        "Click \(model.settings.clickCount) times in a row",
                        value: $model.settings.clickCount,
                        in: UnlockSettings.clickCountRange
                    )
                    Text("Tap-to-click counts as a click too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !model.lockPointer {
                    Text("Turn on \"Lock trackpad and mouse\" to use click unlock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Auto-unlock after")
                    Spacer()
                    TextField("", value: $model.settings.autoUnlockSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Text("s")
                    Stepper(
                        "",
                        value: $model.settings.autoUnlockSeconds,
                        in: UnlockSettings.autoUnlockRange,
                        step: 10
                    )
                    .labelsHidden()
                }

                Text("\(durationText(model.settings.autoUnlockSeconds)). Always on (10 s to 1 h), so the lock can never get stuck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Screen Tab

private struct ScreenSettingsTab: View {
    @ObservedObject var model: FreezeMacModel

    var body: some View {
        Form {
            Section {
                Picker("Displays to black out", selection: $model.settings.blackoutAllDisplays) {
                    Text("All displays").tag(true)
                    Text("Selected displays").tag(false)
                }
                .pickerStyle(.segmented)

                if !model.settings.blackoutAllDisplays {
                    ForEach(model.displays) { display in
                        Toggle(
                            display.isMain ? String(localized: "\(display.name) (main)") : display.name,
                            isOn: Binding(
                                get: { model.settings.blackoutDisplayIDs.contains(display.id) },
                                set: { model.setDisplay(display.id, selected: $0) }
                            )
                        )
                    }
                }
            }

            Section {
                Toggle("Frosty blackout animation", isOn: $model.preferences.frostyAnimationEnabled)
            }

            Section {
                Toggle("Move the lock window around", isOn: $model.settings.moveWindowEnabled)

                if model.settings.moveWindowEnabled {
                    Stepper(
                        "Move every \(model.settings.moveWindowSeconds) s",
                        value: $model.settings.moveWindowSeconds,
                        in: UnlockSettings.moveIntervalRange
                    )
                    Text("Uncovers every part of the screen so you can clean under the window too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
