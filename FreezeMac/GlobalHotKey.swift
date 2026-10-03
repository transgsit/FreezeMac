import Carbon
import Foundation

/// Manages a global hotkey registration via Carbon's RegisterEventHotKey API.
@MainActor
final class GlobalHotKey: ObservableObject {
    @Published var registrationFailed = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    init() {
        installCarbonEventHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func update(enabled: Bool, keyCode: Int, modifiers: UInt32) {
        unregister()
        registrationFailed = false

        guard enabled else { return }

        let hotKeyID = EventHotKeyID(signature: 0x46525A4D, id: 1) // "FRZM", 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            hotKeyRef = ref
            registrationFailed = false
        } else {
            hotKeyRef = nil
            registrationFailed = true
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerCallback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                hotKey.onTrigger?()
            }
            return noErr
        }
        _ = InstallEventHandler(
            GetEventDispatcherTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}

/// Formats a keycode and modifier flags into human-readable glyphs (e.g. ⌃⌥⌘F).
func shortcutGlyphs(keyCode: Int, modifiers: UInt32) -> String {
    var glyphs = ""
    if (modifiers & UInt32(controlKey)) != 0 { glyphs += "⌃" }
    if (modifiers & UInt32(optionKey)) != 0 { glyphs += "⌥" }
    if (modifiers & UInt32(shiftKey)) != 0 { glyphs += "⇧" }
    if (modifiers & UInt32(cmdKey)) != 0 { glyphs += "⌘" }
    glyphs += KeyCodes.name(for: keyCode)
    return glyphs
}
