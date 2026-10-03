import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: FreezeMacModel
    var openMainWindow: () -> Void
    @Environment(\.openSettings) private var openSettings

    @State private var popupWindow: NSWindow?

    var body: some View {
        VStack(spacing: 12) {
            header

            if !model.permissionGranted {
                permissionCard
            }

            contentSection

            bottomSection
        }
        .padding(14)
        .frame(width: 300)
        .fontDesign(.rounded)
        .foregroundStyle(Frosty.ink)
        .tint(Frosty.accent)
        .background(FrostyBackground())
        .background(WindowAccessor(window: $popupWindow))
        .onAppear {
            model.loginItem.refresh()
            model.refreshPermission()
        }
    }

    // MARK: - Header (AC-03)

    private var header: some View {
        HStack(spacing: 10) {
            FrostyLiveMascot(happy: model.phase.isBusy)
                .frame(width: 44, height: 44)

            Text("FreezeMac")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Frosty.ink)

            Spacer()

            FrostyStatusChip(phase: model.phase, statusText: model.statusText)
        }
    }

    // MARK: - Permission Card (AC-04)

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                String(localized: "Grant macOS Accessibility permission first."),
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(Frosty.ink)
            .fixedSize(horizontal: false, vertical: true)

            Button(String(localized: "Grant Permission…")) {
                model.requestPermission()
            }
            .buttonStyle(FrostyPrimaryButtonStyle())
        }
        .frostyCard(padding: 12)
    }

    // MARK: - Content Section (AC-05, AC-06, AC-07, AC-08, AC-10)

    @ViewBuilder
    private var contentSection: some View {
        switch model.phase {
        case .idle:
            idleContent

        case .countdown(let value):
            Button {
                model.cancelCountdown()
            } label: {
                Text("Cancel — locking in \(value)…")
            }
            .buttonStyle(FrostySecondaryButtonStyle())

        case .locked:
            VStack(spacing: 10) {
                Text(model.formattedRemainingTime)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Frosty.ink)

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
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .frostyCard(padding: 14)

        case .ending:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 12) {
            // Mode selection + Auto-unlock chips + Blackout toggle
            VStack(alignment: .leading, spacing: 10) {
                // 1. Mode cards
                HStack(spacing: 8) {
                    FrostyCompactModeCard(
                        title: LockPreset.cleaning.title,
                        symbol: "sparkles",
                        isSelected: model.preset == .cleaning
                    ) {
                        model.selectPreset(.cleaning)
                    }

                    FrostyCompactModeCard(
                        title: LockPreset.kids.title,
                        symbol: "snowflake",
                        isSelected: model.preset == .kids
                    ) {
                        model.selectPreset(.kids)
                    }
                }
                .disabled(model.phase.isBusy)

                // 2. Auto-unlock subhead + 4 chips
                FrostySectionHeader(String(localized: "Auto-Unlock"))

                let options: [Int] = model.preset == .kids
                    ? [600, 1200, 1800, 3600]
                    : [30, 60, 120, 300]

                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { seconds in
                        let isSelected = model.settings.autoUnlockSeconds == seconds
                        Button {
                            model.settings.autoUnlockSeconds = seconds
                        } label: {
                            Text(durationText(seconds))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .buttonStyle(FrostyChipButtonStyle(isSelected: isSelected))
                        .disabled(model.phase.isBusy)
                    }
                }

                // 3. Blackout toggle (cleaning mode only)
                if model.preset != .kids {
                    HStack {
                        Text("Black out displays (cleaning)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Frosty.ink)
                        Spacer()
                        Toggle("", isOn: $model.blackoutScreen)
                            .labelsHidden()
                            .frostySwitch()
                            .disabled(model.phase.isBusy)
                    }
                }
            }
            .frostyCard(padding: 12)

            // Start button (AC-06)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    dismissPopup()
                    model.beginCountdown()
                } label: {
                    Label(
                        model.preset == .kids ? String(localized: "Start Freezing") : String(localized: "Start Cleaning"),
                        systemImage: model.preset == .kids ? "snowflake" : "sparkles"
                    )
                }
                .buttonStyle(FrostyPrimaryButtonStyle())
                .disabled(model.phase.isBusy || !model.permissionGranted || model.startBlockReason != nil)

                if let reason = model.startBlockReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Bottom Section (AC-09)

    private var bottomSection: some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(Frosty.cardEdge)

            HStack {
                Text("Launch at Login")
                    .font(.caption)
                    .foregroundStyle(Frosty.inkSoft)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.loginItem.isEnabled },
                    set: { model.loginItem.setEnabled($0) }
                ))
                .labelsHidden()
                .frostySwitch()
                .controlSize(.small)
            }

            HStack {
                FrostyIconButton(title: String(localized: "Open FreezeMac"), systemImage: "macwindow") {
                    dismissPopup()
                    openMainWindow()
                }

                Spacer()

                FrostyIconButton(title: String(localized: "Settings…"), systemImage: "gearshape") {
                    dismissPopup()
                    openSettings()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")

                Spacer()

                FrostyIconButton(title: String(localized: "Quit FreezeMac"), systemImage: "power") {
                    model.quitApplication()
                }
                .keyboardShortcut("q")
            }
        }
    }

    // MARK: - Dismiss Popup Helper (AC-11)

    private func dismissPopup() {
        popupWindow?.orderOut(nil)
        for window in NSApplication.shared.windows {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || (window is NSPanel && window.level.rawValue >= NSWindow.Level.statusBar.rawValue) {
                window.orderOut(nil)
            }
        }
    }
}

// MARK: - Icon Button with Hover

private struct FrostyIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(isHovered ? Frosty.accent : Frosty.inkSoft)
            .lineLimit(1)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}
