import SwiftUI

struct FreezeMacWindowView: View {
    @ObservedObject var model: FreezeMacModel
    @Environment(\.openSettings) private var openSettings

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

            Label("FreezeMac keeps running in the menu bar when this window is closed", systemImage: "menubar.arrow.up.rectangle")
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
                FrostyStatusChip(phase: model.phase, statusText: model.statusText)
            }

            Spacer()
        }
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

            openSettingsButton

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

    private var openSettingsButton: some View {
        Button {
            openSettings()
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            Label("Open Settings", systemImage: "gearshape")
        }
        .buttonStyle(FrostySecondaryButtonStyle())
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
