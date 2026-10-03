import Carbon
import Foundation

/// General application preferences persisted in UserDefaults.
struct AppPreferences: Codable, Equatable {
    static let allowedCountdownSeconds = [0, 3, 5]

    var openMainWindowAtLaunch = true
    var showRemainingTimeInMenuBar = true
    var hotKeyEnabled = true
    var hotKeyCode = 3 // 'F'
    var hotKeyModifiers = UInt32(cmdKey | optionKey | controlKey)
    var countdownSeconds = 3
    var frostyAnimationEnabled = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openMainWindowAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .openMainWindowAtLaunch) ?? openMainWindowAtLaunch
        showRemainingTimeInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showRemainingTimeInMenuBar) ?? showRemainingTimeInMenuBar
        hotKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotKeyEnabled) ?? hotKeyEnabled
        hotKeyCode = try c.decodeIfPresent(Int.self, forKey: .hotKeyCode) ?? hotKeyCode
        hotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? hotKeyModifiers
        countdownSeconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? countdownSeconds
        frostyAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .frostyAnimationEnabled) ?? frostyAnimationEnabled
    }

    private static let storageKey = "appPreferences.v1"

    static func load() -> AppPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return prefs.clamped()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func clamped() -> AppPreferences {
        var copy = self
        if !Self.allowedCountdownSeconds.contains(copy.countdownSeconds) {
            copy.countdownSeconds = 3
        }
        let mainModifiers = UInt32(cmdKey | optionKey | controlKey)
        if (copy.hotKeyModifiers & mainModifiers) == 0 {
            copy.hotKeyCode = 3
            copy.hotKeyModifiers = mainModifiers
        }
        return copy
    }
}
