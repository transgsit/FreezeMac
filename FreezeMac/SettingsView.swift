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
        .fontDesign(.rounded)
        .tint(Frosty.accent)
    }
}

// MARK: - Toggle Row Helper (AC-16)

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(isDisabled ? Frosty.inkSoft : Frosty.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .frostySwitch()
                .disabled(isDisabled)
        }
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject var model: FreezeMacModel
    @State private var isRecordingHotKey = false
    @State private var hotKeyMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Section 1: Startup
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Startup"))

                    SettingsToggleRow(
                        title: String(localized: "Launch at Login"),
                        isOn: Binding(
                            get: { model.loginItem.isEnabled },
                            set: { model.loginItem.setEnabled($0) }
                        )
                    )

                    if model.loginItem.requiresApproval {
                        HStack {
                            Text("Approval required in System Settings")
                                .font(.caption)
                                .foregroundStyle(Frosty.inkSoft)
                            Spacer()
                            Button(String(localized: "Open Login Items")) {
                                model.loginItem.openLoginItems()
                            }
                            .buttonStyle(FrostyCapsuleButtonStyle())
                        }
                    }

                    if let errorMessage = model.loginItem.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    SettingsToggleRow(
                        title: String(localized: "Open main window at launch"),
                        isOn: $model.preferences.openMainWindowAtLaunch
                    )

                    SettingsToggleRow(
                        title: String(localized: "Show remaining time in menu bar"),
                        isOn: $model.preferences.showRemainingTimeInMenuBar
                    )
                }
                .frostyCard()

                // Section 2: Shortcut
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Shortcut"))

                    SettingsToggleRow(
                        title: String(localized: "Use global shortcut"),
                        isOn: $model.preferences.hotKeyEnabled
                    )

                    if model.preferences.hotKeyEnabled {
                        HStack {
                            Text("Shortcut")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Frosty.ink)
                            Spacer()
                            Button(isRecordingHotKey ? String(localized: "Press shortcut…") : shortcutGlyphs(keyCode: model.preferences.hotKeyCode, modifiers: model.preferences.hotKeyModifiers)) {
                                if isRecordingHotKey {
                                    stopRecordingHotKey()
                                } else {
                                    startRecordingHotKey()
                                }
                            }
                            .buttonStyle(FrostyCapsuleButtonStyle(isHighlighted: isRecordingHotKey))
                        }

                        if model.hotKey.registrationFailed {
                            Text("This shortcut cannot be used")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frostyCard()
            }
            .padding(18)
        }
        .background(FrostyBackground())
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
        ScrollView {
            VStack(spacing: 14) {
                // Section 1: Countdown
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Countdown"))

                    HStack {
                        Text("Countdown before locking")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Frosty.ink)
                        Spacer()
                        Picker("", selection: $model.preferences.countdownSeconds) {
                            Text("None").tag(0)
                            Text("3 s").tag(3)
                            Text("5 s").tag(5)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                        .tint(Frosty.accent)
                    }
                }
                .frostyCard()

                // Section 2: What to Lock
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "What to Lock"))

                    SettingsToggleRow(
                        title: String(localized: "Lock trackpad and mouse"),
                        isOn: $model.lockPointer
                    )

                    SettingsToggleRow(
                        title: String(localized: "Black out displays"),
                        isOn: $model.blackoutScreen
                    )

                    if model.blackoutScreen {
                        Text("Screen blackout also locks the trackpad and mouse.")
                            .font(.caption)
                            .foregroundStyle(Frosty.inkSoft)
                    }
                }
                .frostyCard()
            }
            .padding(18)
        }
        .background(FrostyBackground())
    }
}

// MARK: - Unlock Tab

private struct UnlockSettingsTab: View {
    @ObservedObject var model: FreezeMacModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Section 1: Hold a Key
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Hold a Key"))

                    SettingsToggleRow(
                        title: String(localized: "Hold a key"),
                        isOn: $model.settings.holdKeyEnabled
                    )

                    if model.settings.holdKeyEnabled {
                        HStack {
                            Text("Key")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Frosty.ink)
                            Spacer()
                            Button(model.isRecordingUnlockKey ? String(localized: "Press a key…") : KeyCodes.name(for: model.settings.holdKeyCode)) {
                                if model.isRecordingUnlockKey {
                                    model.endRecordingUnlockKey()
                                } else {
                                    model.beginRecordingUnlockKey()
                                }
                            }
                            .buttonStyle(FrostyCapsuleButtonStyle(isHighlighted: model.isRecordingUnlockKey))
                        }

                        HStack {
                            Text("Hold for \(model.settings.holdKeySeconds) s")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Frosty.ink)
                            Spacer()
                            Stepper("", value: $model.settings.holdKeySeconds, in: UnlockSettings.holdSecondsRange)
                                .labelsHidden()
                                .tint(Frosty.accent)
                        }
                    }
                }
                .frostyCard()

                // Section 2: Type a Word
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Type a Word"))

                    SettingsToggleRow(
                        title: String(localized: "Type a word"),
                        isOn: $model.settings.wordEnabled
                    )

                    if model.settings.wordEnabled {
                        TextField(String(localized: "Word (3–16 letters or digits)"), text: $model.settings.word)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .tint(Frosty.accent)

                        if KeyCodes.codes(for: model.settings.word) == nil {
                            Text("Use only A–Z and 0–9, 3 to 16 characters. Keys are matched by position, so it works while typing Korean too.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frostyCard()

                // Section 3: Click the Trackpad
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Click the Trackpad"))

                    SettingsToggleRow(
                        title: String(localized: "Click the trackpad"),
                        isOn: $model.settings.clickEnabled,
                        isDisabled: !model.lockPointer
                    )

                    if model.settings.clickEnabled && model.lockPointer {
                        HStack {
                            Text("Click \(model.settings.clickCount) times in a row")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Frosty.ink)
                            Spacer()
                            Stepper("", value: $model.settings.clickCount, in: UnlockSettings.clickCountRange)
                                .labelsHidden()
                                .tint(Frosty.accent)
                        }
                        Text("Tap-to-click counts as a click too.")
                            .font(.caption)
                            .foregroundStyle(Frosty.inkSoft)
                    } else if !model.lockPointer {
                        Text("Turn on \"Lock trackpad and mouse\" to use click unlock.")
                            .font(.caption)
                            .foregroundStyle(Frosty.inkSoft)
                    }
                }
                .frostyCard()

                // Section 4: Auto-Unlock
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Auto-Unlock"))

                    HStack {
                        Text("Auto-unlock after")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Frosty.ink)
                        Spacer()
                        TextField("", value: $model.settings.autoUnlockSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .tint(Frosty.accent)
                        Text("s")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Frosty.ink)
                        Stepper(
                            "",
                            value: $model.settings.autoUnlockSeconds,
                            in: UnlockSettings.autoUnlockRange,
                            step: 10
                        )
                        .labelsHidden()
                        .tint(Frosty.accent)
                    }

                    Text("\(durationText(model.settings.autoUnlockSeconds)). Always on (10 s to 1 h), so the lock can never get stuck.")
                        .font(.caption)
                        .foregroundStyle(Frosty.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frostyCard()
            }
            .padding(18)
        }
        .background(FrostyBackground())
    }
}

// MARK: - Screen Tab

private struct ScreenSettingsTab: View {
    @ObservedObject var model: FreezeMacModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Section 1: Black Out Displays
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Black Out Displays"))

                    Picker(String(localized: "Displays to black out"), selection: $model.settings.blackoutAllDisplays) {
                        Text("All displays").tag(true)
                        Text("Selected displays").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .tint(Frosty.accent)

                    if !model.settings.blackoutAllDisplays {
                        VStack(spacing: 8) {
                            ForEach(model.displays) { display in
                                HStack {
                                    Text(display.isMain ? String(localized: "\(display.name) (main)") : display.name)
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(Frosty.ink)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { model.settings.blackoutDisplayIDs.contains(display.id) },
                                        set: { model.setDisplay(display.id, selected: $0) }
                                    ))
                                    .labelsHidden()
                                    .frostySwitch()
                                }
                            }
                        }
                    }
                }
                .frostyCard()

                // Section 2: Frosty Animation
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Frosty Animation"))

                    SettingsToggleRow(
                        title: String(localized: "Frosty blackout animation"),
                        isOn: $model.preferences.frostyAnimationEnabled
                    )
                }
                .frostyCard()

                // Section 3: Move Lock Window
                VStack(alignment: .leading, spacing: 10) {
                    FrostySectionHeader(String(localized: "Move Lock Window"))

                    SettingsToggleRow(
                        title: String(localized: "Move the lock window around"),
                        isOn: $model.settings.moveWindowEnabled
                    )

                    if model.settings.moveWindowEnabled {
                        HStack {
                            Text("Move every \(model.settings.moveWindowSeconds) s")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Frosty.ink)
                            Spacer()
                            Stepper(
                                "",
                                value: $model.settings.moveWindowSeconds,
                                in: UnlockSettings.moveIntervalRange
                            )
                            .labelsHidden()
                            .tint(Frosty.accent)
                        }
                        Text("Uncovers every part of the screen so you can clean under the window too.")
                            .font(.caption)
                            .foregroundStyle(Frosty.inkSoft)
                    }
                }
                .frostyCard()
            }
            .padding(18)
        }
        .background(FrostyBackground())
    }
}

