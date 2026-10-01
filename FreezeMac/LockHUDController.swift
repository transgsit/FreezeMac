import AppKit
import SwiftUI

@MainActor
final class LockHUDController {
    private var panel: NSPanel?
    private var moveTask: Task<Void, Never>?
    private var lastCell: Int?

    func show(model: LockHUDViewModel, moveEvery seconds: Int? = nil) {
        close()

        let hintsHeight = CGFloat(model.unlockHints.count) * 22 + (model.unlockHints.isEmpty ? 0 : 14)
        let size = CGSize(width: 390, height: 122 + hintsHeight + (model.pointerLocked ? 0 : 64))
        let frame = Self.frame(size: size, centered: model.blackoutEnabled)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(rootView: LockHUDView(model: model))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = model.blackoutEnabled || model.pointerLocked
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            : .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = model.pointerLocked
        panel.orderFrontRegardless()

        self.panel = panel

        if let seconds {
            startMoving(every: seconds)
        }
    }

    func close() {
        moveTask?.cancel()
        moveTask = nil
        lastCell = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    /// Hops the window to a different cell of a 3×3 grid every few seconds so no
    /// part of the screen stays covered for long. The text stays readable the
    /// whole time because the window glides instead of disappearing.
    private func startMoving(every seconds: Int) {
        moveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.moveToNextCell()
            }
        }
    }

    private func moveToNextCell() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        // Never run away from a slider the user is dragging right now.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let cells = (0..<9).filter { $0 != lastCell }
        guard let cell = cells.randomElement() else { return }
        lastCell = cell

        let visible = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 24
        let spanX = max(0, visible.width - size.width - margin * 2)
        let spanY = max(0, visible.height - size.height - margin * 2)

        // A little jitter keeps the covered spots from repeating exactly.
        let jitterX = CGFloat.random(in: -0.08...0.08) * spanX
        let jitterY = CGFloat.random(in: -0.08...0.08) * spanY

        let x = visible.minX + margin + spanX * CGFloat(cell % 3) / 2 + jitterX
        let y = visible.maxY - margin - size.height - spanY * CGFloat(cell / 3) / 2 + jitterY
        let target = CGRect(
            x: min(max(x, visible.minX + margin), visible.maxX - margin - size.width),
            y: min(max(y, visible.minY + margin), visible.maxY - margin - size.height),
            width: size.width,
            height: size.height
        )

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        }
    }

    private static func frame(size: CGSize, centered: Bool) -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = centered
            ? visible.midY - size.height / 2
            : visible.maxY - size.height - 28
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
