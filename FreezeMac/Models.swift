import Foundation

enum LockPhase: Equatable {
    case idle
    case countdown(Int)
    case locked
    case ending

    var isBusy: Bool {
        self != .idle
    }
}

enum InputSignal: Sendable {
    case unlockKeyChanged(isDown: Bool)
    case unlockRequested
    case tapDisabled
}

enum InputBlockerError: LocalizedError {
    case permissionMissing
    case tapCreationFailed
    case tapEnableFailed
    case pointerLockFailed
    case invalidUnlockWord

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            return String(localized: "To lock the keyboard, allow FreezeMac in System Settings › Privacy & Security › Accessibility.")
        case .tapCreationFailed:
            return String(localized: "macOS could not create the input filter. Check the permission and try again.")
        case .tapEnableFailed:
            return String(localized: "The input filter was created but could not be enabled. The keyboard was not locked.")
        case .pointerLockFailed:
            return String(localized: "macOS could not lock the pointer. FreezeMac did not start cleaning mode for safety.")
        case .invalidUnlockWord:
            return String(localized: "The unlock word must be 3–16 letters (A–Z) or digits. Fix it or turn the word unlock off.")
        }
    }
}

struct LockOptions: Equatable {
    let lockPointer: Bool
    let blackoutScreen: Bool
    let durationSeconds: Int
    let triggers: UnlockTriggers
    let holdSeconds: Int
    let unlockHints: [String]
}

@MainActor
final class LockHUDViewModel: ObservableObject {
    @Published var remainingSeconds: Int

    let totalSeconds: Int
    let pointerLocked: Bool
    let blackoutEnabled: Bool
    let unlockHints: [String]
    let onUnlock: () -> Void

    init(
        remainingSeconds: Int,
        totalSeconds: Int,
        pointerLocked: Bool,
        blackoutEnabled: Bool,
        unlockHints: [String],
        onUnlock: @escaping () -> Void
    ) {
        self.remainingSeconds = remainingSeconds
        self.totalSeconds = max(totalSeconds, 1)
        self.pointerLocked = pointerLocked
        self.blackoutEnabled = blackoutEnabled
        self.unlockHints = unlockHints
        self.onUnlock = onUnlock
    }

    var remainingFraction: Double {
        min(max(Double(remainingSeconds) / Double(totalSeconds), 0), 1)
    }

    var formattedRemainingTime: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}
