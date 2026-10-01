import AppKit
import Foundation

/// User-adjustable unlock, auto-unlock and blackout settings, persisted in UserDefaults.
struct UnlockSettings: Codable, Equatable {
    static let holdSecondsRange = 1...30
    static let clickCountRange = 1...10
    static let autoUnlockRange = 10...3600
    static let wordLengthRange = 3...16
    static let moveIntervalRange = 2...10

    var holdKeyEnabled = true
    var holdKeyCode = 53
    var holdKeySeconds = 3

    var clickEnabled = false
    var clickCount = 3

    var wordEnabled = true
    var word = "NOW"

    var autoUnlockSeconds = 60

    var blackoutAllDisplays = true
    var blackoutDisplayIDs: [UInt32] = []

    var moveWindowEnabled = true
    var moveWindowSeconds = 3

    init() {}

    // Decode field by field so settings saved by an older version still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holdKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .holdKeyEnabled) ?? holdKeyEnabled
        holdKeyCode = try c.decodeIfPresent(Int.self, forKey: .holdKeyCode) ?? holdKeyCode
        holdKeySeconds = try c.decodeIfPresent(Int.self, forKey: .holdKeySeconds) ?? holdKeySeconds
        clickEnabled = try c.decodeIfPresent(Bool.self, forKey: .clickEnabled) ?? clickEnabled
        clickCount = try c.decodeIfPresent(Int.self, forKey: .clickCount) ?? clickCount
        wordEnabled = try c.decodeIfPresent(Bool.self, forKey: .wordEnabled) ?? wordEnabled
        word = try c.decodeIfPresent(String.self, forKey: .word) ?? word
        autoUnlockSeconds = try c.decodeIfPresent(Int.self, forKey: .autoUnlockSeconds) ?? autoUnlockSeconds
        blackoutAllDisplays = try c.decodeIfPresent(Bool.self, forKey: .blackoutAllDisplays) ?? blackoutAllDisplays
        blackoutDisplayIDs = try c.decodeIfPresent([UInt32].self, forKey: .blackoutDisplayIDs) ?? blackoutDisplayIDs
        moveWindowEnabled = try c.decodeIfPresent(Bool.self, forKey: .moveWindowEnabled) ?? moveWindowEnabled
        moveWindowSeconds = try c.decodeIfPresent(Int.self, forKey: .moveWindowSeconds) ?? moveWindowSeconds
    }

    private static let storageKey = "unlockSettings.v1"

    static var hasSavedValue: Bool {
        UserDefaults.standard.data(forKey: storageKey) != nil
    }

    static func load() -> UnlockSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(UnlockSettings.self, from: data) else {
            return UnlockSettings()
        }

        // One-time move of the saved auto-unlock time to the new 1-minute default.
        let migrationKey = "migration.autoUnlock60"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            settings.autoUnlockSeconds = 60
            UserDefaults.standard.set(true, forKey: migrationKey)
            settings.save()
        }
        return settings.clamped()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func clamped() -> UnlockSettings {
        var copy = self
        copy.holdKeySeconds = min(max(holdKeySeconds, Self.holdSecondsRange.lowerBound), Self.holdSecondsRange.upperBound)
        copy.clickCount = min(max(clickCount, Self.clickCountRange.lowerBound), Self.clickCountRange.upperBound)
        copy.moveWindowSeconds = min(max(moveWindowSeconds, Self.moveIntervalRange.lowerBound), Self.moveIntervalRange.upperBound)
        copy.autoUnlockSeconds = min(max(autoUnlockSeconds, Self.autoUnlockRange.lowerBound), Self.autoUnlockRange.upperBound)
        return copy
    }

    /// Human-readable list of the unlock methods that are active for a session.
    func hints(lockPointer: Bool) -> [String] {
        var hints: [String] = []
        if holdKeyEnabled {
            let key = KeyCodes.name(for: holdKeyCode)
            hints.append(String(localized: "Hold \(key) for \(holdKeySeconds) s"))
        }
        if wordEnabled {
            let typed = word.uppercased()
            hints.append(String(localized: "Type \(typed)"))
        }
        if clickEnabled && lockPointer {
            hints.append(String(localized: "Click \(clickCount)×"))
        }
        return hints
    }
}

/// What the event tap watches for. A snapshot taken when a session starts.
struct UnlockTriggers: Equatable {
    var holdKeyCode: Int64?
    var wordKeyCodes: [Int64]?
    var clickCount: Int?

    init() {}

    init(settings: UnlockSettings, lockPointer: Bool) {
        holdKeyCode = settings.holdKeyEnabled ? Int64(settings.holdKeyCode) : nil
        wordKeyCodes = settings.wordEnabled ? KeyCodes.codes(for: settings.word) : nil
        // Clicks only reach the event tap when the pointer is locked.
        clickCount = settings.clickEnabled && lockPointer ? settings.clickCount : nil
    }
}

struct DisplayInfo: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isMain: Bool

    @MainActor
    static func current() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return DisplayInfo(id: id, name: screen.localizedName, isMain: screen == NSScreen.main)
        }
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Physical key positions (ANSI layout). Keycodes identify the key, not the typed
/// character, so they behave the same while a Korean input source is active.
enum KeyCodes {
    private static let letters: [Character: Int64] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40,
        "N": 45, "M": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    ]

    private static let specialNames: [Int: String] = [
        53: "Esc", 49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Fn-Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    /// Key positions for a word, or nil if it has unsupported characters or a bad length.
    static func codes(for word: String) -> [Int64]? {
        let characters = Array(word.uppercased())
        guard UnlockSettings.wordLengthRange.contains(characters.count) else { return nil }

        var result: [Int64] = []
        for character in characters {
            guard let code = letters[character] else { return nil }
            result.append(code)
        }
        return result
    }

    static func name(for keyCode: Int) -> String {
        if let name = specialNames[keyCode] { return name }
        if let match = letters.first(where: { $0.value == Int64(keyCode) }) { return String(match.key) }
        return String(localized: "Key \(keyCode)")
    }
}

/// "10 s", "1 min 30 s", "2 min", "1 h".
func durationText(_ seconds: Int) -> String {
    if seconds < 60 { return String(localized: "\(seconds) s") }
    if seconds < 3600 {
        let minutes = seconds / 60, rest = seconds % 60
        return rest == 0 ? String(localized: "\(minutes) min") : String(localized: "\(minutes) min \(rest) s")
    }
    let hours = seconds / 3600, minutes = seconds % 3600 / 60
    return minutes == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(minutes) min")
}

/// The session options a preset controls. Unlock key and word are left alone on purpose.
struct LockProfile: Equatable {
    var lockPointer: Bool
    var blackoutScreen: Bool
    var moveWindowEnabled: Bool
    var clickEnabled: Bool
}

enum LockPreset: String, CaseIterable, Identifiable {
    case cleaning
    case kids

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleaning: return String(localized: "Cleaning")
        case .kids: return String(localized: "Kid watching")
        }
    }

    var detail: String {
        switch self {
        case .cleaning:
            return String(localized: "Wipe the keyboard and screen. The lock window moves so you can clean under it.")
        case .kids:
            return String(localized: "Keep a video playing. Screen stays visible and the lock window stays put.")
        }
    }

    var profile: LockProfile {
        switch self {
        case .cleaning:
            return LockProfile(lockPointer: true, blackoutScreen: false, moveWindowEnabled: true, clickEnabled: false)
        case .kids:
            return LockProfile(lockPointer: true, blackoutScreen: false, moveWindowEnabled: false, clickEnabled: false)
        }
    }

    private static let storageKey = "preset.v1"

    static func stored() -> LockPreset? {
        UserDefaults.standard.string(forKey: storageKey).flatMap(LockPreset.init(rawValue:))
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }

    static func clearStored() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
