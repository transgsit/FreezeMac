import AppKit
import SwiftUI

@MainActor
final class CountdownHUDModel: ObservableObject {
    enum State: Equatable {
        case counting(Int)
        case canceled
    }

    @Published var state: State = .counting(3)
    @Published var isKidsMode: Bool = false
    var onCancel: (() -> Void)?
}

@MainActor
final class CountdownHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var generation = 0
    private let model = CountdownHUDModel()

    func show(seconds: Int, isKidsMode: Bool, onCancel: @escaping () -> Void) {
        dismissTask?.cancel()
        dismissTask = nil
        generation += 1

        model.state = .counting(seconds)
        model.isKidsMode = isKidsMode
        model.onCancel = onCancel

        if panel == nil {
            let panel = makePanel()
            panel.contentView = NSHostingView(rootView: CountdownHUDView(model: model))
            self.panel = panel
        }

        updatePosition()
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
    }

    func update(seconds: Int) {
        model.state = .counting(seconds)
        updatePosition()
    }

    func showCanceled() {
        dismissTask?.cancel()
        guard panel != nil else { return }

        let id = generation
        model.state = .canceled
        updatePosition()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, self.generation == id, !Task.isCancelled else { return }
            await self.fadeOut(duration: 0.2)
            guard self.generation == id, !Task.isCancelled else { return }
            self.closeImmediately()
        }
    }

    func closeImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        generation += 1
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    func fadeOutAndClose(duration: Double = 0.15) async {
        dismissTask?.cancel()
        dismissTask = nil
        let id = generation
        await fadeOut(duration: duration)
        guard generation == id else { return }
        closeImmediately()
    }

    private func fadeOut(duration: Double) async {
        guard let panel, panel.isVisible else { return }
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            } completionHandler: {
                continuation.resume()
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        return panel
    }

    private func updatePosition() {
        guard let panel, let screen = NSScreen.main else { return }
        let width: CGFloat = 280
        let targetHeight: CGFloat
        if let contentView = panel.contentView {
            let fit = contentView.fittingSize
            targetHeight = fit.height > 50 ? fit.height : 260
        } else {
            targetHeight = 260
        }
        let frame = screen.frame
        let x = frame.midX - width / 2
        let y = frame.midY - targetHeight / 2
        panel.setFrame(CGRect(x: x, y: y, width: width, height: targetHeight), display: true)
        panel.invalidateShadow()
    }
}

struct CountdownHUDView: View {
    @ObservedObject var model: CountdownHUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            FrostyLiveMascot(happy: false)
                .frame(width: 48, height: 48)

            switch model.state {
            case .counting(let seconds):
                Text("\(seconds)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Frosty.accent)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: seconds)

                Text(model.isKidsMode ? String(localized: "Freezing your Mac…") : String(localized: "Locking the keyboard…"))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Frosty.ink)

                HStack(spacing: 6) {
                    escBadge
                    Text("to cancel")
                        .font(.caption)
                        .foregroundStyle(Frosty.inkSoft)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Press ESC to cancel"))

                Button(String(localized: "Cancel")) {
                    model.onCancel?()
                }
                .buttonStyle(FrostySecondaryButtonStyle())
                .padding(.top, 2)

            case .canceled:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Frosty.accent)

                    Text("Canceled")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Frosty.ink)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(18)
        .frame(width: 280)
        .fontDesign(.rounded)
        // Same opaque frosted glass as the lock window, so it stays readable over anything.
        // The panel draws the shadow; a SwiftUI shadow here would halo every child view.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Frosty.backgroundTop.opacity(0.78), Frosty.backgroundBottom.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Frosty.cardEdge, lineWidth: 1.5)
        )
    }

    private var escBadge: some View {
        Text("ESC")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Frosty.inkSoft)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Frosty.inkSoft.opacity(0.5), lineWidth: 1)
            )
    }
}
