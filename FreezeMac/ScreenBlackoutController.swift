import AppKit
import SwiftUI

@MainActor
final class ScreenBlackoutController {
    private struct Entry {
        let window: NSWindow
        let stage: BlackoutStage
    }

    private var entries: [Entry] = []
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0
    private var isLeaving = false

    /// Frosty hops into the island and the screen turns black from there.
    func show(screens: [NSScreen], frostyAnimationEnabled: Bool = true) {
        tearDownNow()
        generation += 1

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !frostyAnimationEnabled
        // Frosty lives on the screen with the notch, else the main screen.
        let frostyScreen = screens.first { $0.islandGeometry.isHardwareNotch }
            ?? screens.first { $0 == NSScreen.main }
            ?? screens.first

        entries = screens.map { screen in
            let stage = BlackoutStage(
                screenSize: screen.frame.size,
                island: screen.islandGeometry,
                showsFrosty: screen == frostyScreen,
                reduceMotion: reduceMotion
            )
            return Entry(window: makeWindow(for: screen, stage: stage), stage: stage)
        }

        entries.forEach { $0.window.orderFrontRegardless() }
        tasks = entries.map { entry in
            Task { await entry.stage.playEntry() }
        }
    }

    /// Plays Frosty's pop-out, then removes the windows. Input is already unlocked by then.
    func hide(animated: Bool = true) {
        guard !entries.isEmpty, !isLeaving else { return }
        guard animated else {
            tearDownNow()
            return
        }

        isLeaving = true
        tasks.forEach { $0.cancel() }

        let id = generation
        let leaving = entries
        let entryFinished = leaving.allSatisfy { $0.stage.isEntryFinished }
        var remaining = leaving.count

        tasks = leaving.map { entry in
            Task { [weak self] in
                if entryFinished {
                    await entry.stage.playExit()
                } else {
                    await entry.stage.playQuickFade()
                }
                guard let self, self.generation == id, !Task.isCancelled else { return }
                remaining -= 1
                if remaining == 0 {
                    self.tearDownNow()
                }
            }
        }
    }

    private func tearDownNow() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        entries.forEach {
            $0.window.orderOut(nil)
            $0.window.contentView = nil
        }
        entries.removeAll()
        isLeaving = false
    }

    private func makeWindow(for screen: NSScreen, stage: BlackoutStage) -> NSWindow {
        // contentRect is relative to `screen`, so the frame is pinned explicitly below.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: BlackoutStageView(stage: stage))
        window.setFrame(screen.frame, display: true)
        return window
    }
}

@MainActor
final class PointerShieldController {
    private var windows: [NSPanel] = []
    private var cursorGuardTask: Task<Void, Never>?
    private var cursorAnchor: CGPoint?
    private var cursorIsHidden = false

    var isActive: Bool {
        !windows.isEmpty
    }

    func show() {
        hide()

        cursorAnchor = CGEvent(source: nil)?.location
        _ = CGAssociateMouseAndMouseCursorPosition(0)
        if let cursorAnchor {
            _ = CGWarpMouseCursorPosition(cursorAnchor)
        }
        NSCursor.hide()
        cursorIsHidden = true

        cursorGuardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled, let self, let cursorAnchor else { return }

                // macOS may temporarily reconnect the mouse and cursor when a
                // system window appears or focus changes. Keep pinning it to
                // the same screen position while the lock is active.
                _ = CGAssociateMouseAndMouseCursorPosition(0)
                _ = CGWarpMouseCursorPosition(cursorAnchor)
            }
        }

        windows = NSScreen.screens.map { screen in
            let panel = PointerShieldPanel(
                contentRect: CGRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            let shieldView = PointerShieldView(frame: CGRect(origin: .zero, size: screen.frame.size))
            shieldView.autoresizingMask = [.width, .height]

            panel.contentView = shieldView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.worksWhenModal = true
            panel.level = .screenSaver
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return panel
        }
    }

    func hide() {
        cursorGuardTask?.cancel()
        cursorGuardTask = nil

        windows.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
        windows.removeAll()

        _ = CGAssociateMouseAndMouseCursorPosition(1)
        cursorAnchor = nil

        if cursorIsHidden {
            NSCursor.unhide()
            cursorIsHidden = false
        }
    }
}

private final class PointerShieldPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PointerShieldView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        acceptsTouchEvents = true
        wantsRestingTouches = true
        allowedTouchTypes = [.direct, .indirect]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        acceptsTouchEvents = true
        wantsRestingTouches = true
        allowedTouchTypes = [.direct, .indirect]
    }

    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
    override func pressureChange(with event: NSEvent) {}
    override func beginGesture(with event: NSEvent) {}
    override func endGesture(with event: NSEvent) {}
    override func touchesBegan(with event: NSEvent) {}
    override func touchesMoved(with event: NSEvent) {}
    override func touchesEnded(with event: NSEvent) {}
    override func touchesCancelled(with event: NSEvent) {}
}
