import SwiftUI

struct FreezeMacWindowView: View {
    @ObservedObject var model: FreezeMacModel
    @AppStorage("advancedOptionsExpanded") private var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.permissionGranted {
                permissionCard
            }

            controls

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("FreezeMac quits completely when you close this window", systemImage: "power")
                .font(.caption)
                .foregroundStyle(Frosty.inkSoft)
        }
        .padding(20)
        .fontDesign(.rounded)
        .foregroundStyle(Frosty.ink)
        .tint(Frosty.accent)
        .background(FrostyBackground())
        .task {
            while !Task.isCancelled {
                model.refreshPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            FrostyLiveMascot(happy: model.phase.isBusy)
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text("FreezeMac")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                statusChip
            }

            Spacer()
        }
    }

    private var statusChip: some View {
        let tint: Color = model.phase.isBusy ? .orange : Frosty.accent
        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(model.statusText)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }

    // MARK: Permission

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Allow access to lock input", systemImage: "hand.raised.fill")
                .font(.headline)

            Text("macOS only lets apps you approve discard keyboard and trackpad input. FreezeMac does not record or store keystrokes.")
                .font(.subheadline)
                .foregroundStyle(Frosty.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text("Turn on FreezeMac under Privacy & Security › Accessibility. This window updates by itself once access is granted. If FreezeMac is already listed but still not working, remove it with the − button and add it again.")
                .font(.caption)
                .foregroundStyle(Frosty.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Grant Permission") {
                    model.requestPermission()
                }
                .buttonStyle(FrostyPrimaryButtonStyle())

                Button("Open System Settings") {
                    model.openAccessibilitySettings()
                }
                .buttonStyle(FrostySecondaryButtonStyle())
            }
        }
        .frostyCard()
    }

    // MARK: Main controls: only what people change every time

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            modePicker

            lockOptions

            summaryCard

            advancedOptions

            actionButton
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ModeCard(
                    title: LockPreset.cleaning.title,
                    subtitle: String(localized: "Wipe keys and screen"),
                    symbol: "sparkles",
                    isSelected: model.preset == .cleaning
                ) {
                    model.selectPreset(.cleaning)
                }

                ModeCard(
                    title: LockPreset.kids.title,
                    subtitle: String(localized: "Keep a video playing"),
                    symbol: "snowflake",
                    isSelected: model.preset == .kids
                ) {
                    model.selectPreset(.kids)
                }
            }
            .disabled(model.phase.isBusy)

            Text(model.preset?.detail ?? String(localized: "Custom settings. Tap a mode to reset to its defaults."))
                .font(.caption)
                .foregroundStyle(Frosty.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lockOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Lock trackpad and mouse", isOn: $model.lockPointer)
                .disabled(model.phase.isBusy)

            // A child watching a video needs the screen visible, so this mode hides the option.
            if model.preset != .kids {
                Toggle("Black out displays", isOn: $model.blackoutScreen)
                    .disabled(model.phase.isBusy)

                if model.blackoutScreen {
                    Text("Screen blackout also locks the trackpad and mouse.")
                        .font(.caption)
                        .foregroundStyle(Frosty.inkSoft)
                }
            }

            // A video runs for minutes, so this mode sets the time in minutes.
            if model.preset == .kids {
                Divider()
                freezeMinutes
            }
        }
        .frostySwitch()
        .frostyCard()
    }

    private var freezeMinutes: some View {
        let minutes = Binding<Int>(
            get: { max(1, model.settings.autoUnlockSeconds / 60) },
            set: { model.settings.autoUnlockSeconds = $0 * 60 }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Freeze for")
                Spacer()
                TextField("", value: minutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("min")
                Stepper("", value: minutes, in: 1...60)
                    .labelsHidden()
            }
            Text("Unlocks by itself when the time is up, even if every other way out is forgotten.")
                .font(.caption)
                .foregroundStyle(Frosty.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.phase.isBusy)
    }

    /// One look at what Start will do, including the auto-unlock guarantee.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(model.lockSummary, systemImage: "lock.fill")
            Label(model.unlockLine, systemImage: "lock.open.fill")
            Label(model.autoUnlockLine, systemImage: "timer")
        }
        .font(.subheadline)
        .labelStyle(SummaryLabelStyle())
        .frostyCard(padding: 12)
    }

    private var advancedOptions: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                if model.blackoutScreen {
                    displayPicker
                    Divider()
                }

                windowMovement

                Divider()

                unlockSettings
            }
            .padding(.top, 12)
        } label: {
            Text("Advanced options")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .frostyCard()
    }

    @ViewBuilder
    private var actionButton: some View {
        switch model.phase {
        case .idle:
            if model.permissionGranted {
                Button {
                    model.beginCountdown()
                } label: {
                    Label(
                        model.preset == .kids ? String(localized: "Start Freezing") : String(localized: "Start Cleaning"),
                        systemImage: model.preset == .kids ? "snowflake" : "sparkles"
                    )
                }
                .buttonStyle(FrostyPrimaryButtonStyle())
                .disabled(model.startBlockReason != nil)

                if let reason = model.startBlockReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button {
                    model.requestPermission()
                } label: {
                    Label("Allow access to start", systemImage: "hand.raised.fill")
                }
                .buttonStyle(FrostyPrimaryButtonStyle())
            }

        case .countdown(let value):
            Button {
                model.cancelCountdown()
            } label: {
                Text("Cancel — locking in \(value)…")
            }
            .buttonStyle(FrostySecondaryButtonStyle())

        case .locked:
            if !model.lockPointer {
                Button {
                    model.endSession()
                } label: {
                    Text("Unlock")
                }
                .buttonStyle(FrostySecondaryButtonStyle())
            } else {
                Text(model.unlockSummary)
                    .font(.caption)
                    .foregroundStyle(Frosty.inkSoft)
            }

        case .ending:
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Advanced options: set once and forget

    private var windowMovement: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Move the lock window around", isOn: $model.settings.moveWindowEnabled)
                .frostySwitch()
            if model.settings.moveWindowEnabled {
                Stepper(
                    "Move every \(model.settings.moveWindowSeconds) s",
                    value: $model.settings.moveWindowSeconds,
                    in: UnlockSettings.moveIntervalRange
                )
                .font(.subheadline)
                Text("Uncovers every part of the screen so you can clean under the window too.")
                    .font(.caption)
                    .foregroundStyle(Frosty.inkSoft)
            }
        }
        .disabled(model.phase.isBusy)
    }

    private var unlockSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlock settings")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))

            HStack {
                Toggle("Hold a key", isOn: $model.settings.holdKeyEnabled)
                    .frostySwitch()
                Spacer()
                Button(model.isRecordingUnlockKey ? "Press a key…" : KeyCodes.name(for: model.settings.holdKeyCode)) {
                    if model.isRecordingUnlockKey {
                        model.endRecordingUnlockKey()
                    } else {
                        model.beginRecordingUnlockKey()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!model.settings.holdKeyEnabled)
            }
            if model.settings.holdKeyEnabled {
                Stepper(
                    "Hold for \(model.settings.holdKeySeconds) s",
                    value: $model.settings.holdKeySeconds,
                    in: UnlockSettings.holdSecondsRange
                )
                .font(.subheadline)
            }

            Toggle("Type a word", isOn: $model.settings.wordEnabled)
                .frostySwitch()
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

            Toggle("Click the trackpad", isOn: $model.settings.clickEnabled)
                .frostySwitch()
                .disabled(!model.lockPointer)
            if model.settings.clickEnabled && model.lockPointer {
                Stepper(
                    "Click \(model.settings.clickCount) times in a row",
                    value: $model.settings.clickCount,
                    in: UnlockSettings.clickCountRange
                )
                .font(.subheadline)
                Text("Tap-to-click counts as a click too.")
                    .font(.caption)
                    .foregroundStyle(Frosty.inkSoft)
            } else if !model.lockPointer {
                Text("Turn on \"Lock trackpad and mouse\" to use click unlock.")
                    .font(.caption)
                    .foregroundStyle(Frosty.inkSoft)
            }

            // Kid watching sets the time in minutes on the main screen instead.
            if model.preset != .kids {
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
                    .foregroundStyle(Frosty.inkSoft)
            }
        }
        .disabled(model.phase.isBusy)
    }

    private var displayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Displays to black out", selection: $model.settings.blackoutAllDisplays) {
                Text("All displays").tag(true)
                Text("Selected displays").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(model.phase.isBusy)

            if !model.settings.blackoutAllDisplays {
                ForEach(model.displays) { display in
                    Toggle(
                        display.isMain ? String(localized: "\(display.name) (main)") : display.name,
                        isOn: Binding(
                            get: { model.settings.blackoutDisplayIDs.contains(display.id) },
                            set: { model.setDisplay(display.id, selected: $0) }
                        )
                    )
                    .frostySwitch()
                    .disabled(model.phase.isBusy)
                }
            }
        }
    }
}

/// Icon column + wrapping text, so long summary lines stay aligned.
private struct SummaryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .foregroundStyle(Frosty.accent)
                .frame(width: 16)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
