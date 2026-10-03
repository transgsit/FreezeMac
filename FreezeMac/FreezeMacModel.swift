import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class FreezeMacModel: ObservableObject {
    @Published private(set) var phase: LockPhase = .idle
    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var remainingSeconds = 0
    @Published var errorMessage: String?

    @Published var lockPointer = UserDefaults.standard.bool(forKey: "session.lockPointer") {
        didSet {
            if !lockPointer && blackoutScreen {
                blackoutScreen = false
            }
            UserDefaults.standard.set(lockPointer, forKey: "session.lockPointer")
            clearPresetIfChanged()
        }
    }

    @Published var blackoutScreen = UserDefaults.standard.bool(forKey: "session.blackoutScreen") {
        didSet {
            if blackoutScreen && !lockPointer {
                lockPointer = true
            }
            UserDefaults.standard.set(blackoutScreen, forKey: "session.blackoutScreen")
            clearPresetIfChanged()
        }
    }

    @Published var settings = UnlockSettings.load() {
        didSet {
            let clamped = settings.clamped()
            if clamped != settings {
                settings = clamped
                return
            }
            settings.save()
            clearPresetIfChanged()
        }
    }

    @Published var preferences = AppPreferences.load() {
        didSet {
            let clamped = preferences.clamped()
            if clamped != preferences {
                preferences = clamped
                return
            }
            preferences.save()
            syncHotKey()
        }
    }

    let loginItem = LoginItem()
    let hotKey = GlobalHotKey()

    /// nil when the values were adjusted by hand (no mode button is highlighted).
    @Published private(set) var preset = LockPreset.stored()
    private var isApplyingPreset = false

    @Published private(set) var displays = DisplayInfo.current()
    @Published private(set) var isRecordingUnlockKey = false

    private let inputBlocker = InputBlocker()
    private let blackoutController = ScreenBlackoutController()
    private let pointerShieldController = PointerShieldController()
    private let hudController = LockHUDController()

    private var countdownTask: Task<Void, Never>?
    private var sessionTimerTask: Task<Void, Never>?
    private var escapeHoldTask: Task<Void, Never>?
    private var notificationTokens: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var hudModel: LockHUDViewModel?
    private var keyRecorder: Any?
    private var activeHoldSeconds = 3

    init() {
        refreshPermission()

        loginItem.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        hotKey.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        inputBlocker.onSignal = { [weak self] signal in
            Task { @MainActor in
                self?.handle(signal: signal)
            }
        }

        observeSafetyNotifications()
        observeDisplayChanges()
        observeAppActivation()

        hotKey.onTrigger = { [weak self] in
            self?.handleGlobalHotKey()
        }
        syncHotKey()

        // First launch: start from the Cleaning preset. Anyone with saved
        // settings keeps their values and starts with no mode highlighted.
        if LockPreset.stored() == nil && !UnlockSettings.hasSavedValue {
            applyPreset(.cleaning)
        }
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    var statusText: String {
        switch phase {
        case .idle:
            return String(localized: "Keyboard is available")
        case .countdown(let value):
            return String(localized: "Locking in \(value)…")
        case .locked:
            return String(localized: "Keyboard locked")
        case .ending:
            return String(localized: "Unlocking…")
        }
    }

    var formattedRemainingTime: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var menuStatusText: String {
        switch phase {
        case .idle:
            return String(localized: "Keyboard is available")
        case .countdown(let value):
            return String(localized: "Locking in \(value)…")
        case .locked:
            return String(localized: "Locked · Time remaining \(formattedRemainingTime)")
        case .ending:
            return String(localized: "Unlocking…")
        }
    }

    /// Text shown in the settings window while locked: which ways out are active.
    var unlockSummary: String {
        unlockLine + " · " + autoUnlockLine
    }

    // MARK: Summary shown before starting

    var lockSummary: String {
        var parts = [String(localized: "keyboard")]
        if lockPointer { parts.append(String(localized: "trackpad & mouse")) }
        if blackoutScreen {
            parts.append(settings.blackoutAllDisplays
                ? String(localized: "black out all displays")
                : String(localized: "black out chosen displays"))
        }
        let list = parts.joined(separator: ", ")
        return String(localized: "Locks: \(list)")
    }

    var unlockLine: String {
        var ways = settings.hints(lockPointer: lockPointer)
        if !lockPointer { ways.append(String(localized: "slide to unlock")) }
        let list = ways.joined(separator: " · ")
        return ways.isEmpty ? String(localized: "No manual unlock is on") : String(localized: "Unlock: \(list)")
    }

    var autoUnlockLine: String {
        let duration = durationText(settings.autoUnlockSeconds)
        return String(localized: "Auto-unlocks after \(duration), no matter what")
    }

    /// Why Start is blocked, or nil when it is safe to start.
    var startBlockReason: String? {
        if settings.wordEnabled && KeyCodes.codes(for: settings.word) == nil {
            return String(localized: "The unlock word must be 3–16 letters (A–Z) or digits. Fix it under Advanced options.")
        }
        if lockPointer && settings.hints(lockPointer: true).isEmpty {
            return String(localized: "Turn on at least one way to unlock under Advanced options.")
        }
        return nil
    }

    // MARK: Presets

    func selectPreset(_ newPreset: LockPreset) {
        guard !phase.isBusy else { return }
        applyPreset(newPreset)
    }

    private var currentProfile: LockProfile {
        LockProfile(
            lockPointer: lockPointer,
            blackoutScreen: blackoutScreen,
            moveWindowEnabled: settings.moveWindowEnabled,
            clickEnabled: settings.clickEnabled
        )
    }

    private func applyPreset(_ newPreset: LockPreset) {
        let profile = newPreset.profile
        isApplyingPreset = true
        lockPointer = profile.lockPointer
        blackoutScreen = profile.blackoutScreen
        settings.moveWindowEnabled = profile.moveWindowEnabled
        settings.clickEnabled = profile.clickEnabled
        if newPreset == .kids {
            // Kid watching sets its time in whole minutes.
            let seconds = settings.autoUnlockSeconds
            settings.autoUnlockSeconds = min(3600, max(60, (seconds + 59) / 60 * 60))
        }
        isApplyingPreset = false
        preset = newPreset
        newPreset.save()
    }

    /// Editing any value a preset controls clears the highlighted mode.
    private func clearPresetIfChanged() {
        guard !isApplyingPreset, let preset, preset.profile != currentProfile else { return }
        self.preset = nil
        LockPreset.clearStored()
    }

    func beginRecordingUnlockKey() {
        endRecordingUnlockKey()
        isRecordingUnlockKey = true
        keyRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.settings.holdKeyCode = Int(event.keyCode)
                self?.endRecordingUnlockKey()
            }
            return nil
        }
    }

    func endRecordingUnlockKey() {
        if let keyRecorder {
            NSEvent.removeMonitor(keyRecorder)
        }
        keyRecorder = nil
        isRecordingUnlockKey = false
    }

    func setDisplay(_ id: UInt32, selected: Bool) {
        var ids = Set(settings.blackoutDisplayIDs)
        if selected { ids.insert(id) } else { ids.remove(id) }
        settings.blackoutDisplayIDs = ids.sorted()
    }

    #if SNAPSHOT_HARNESS
    var debugPermission: Bool?
    #endif

    func refreshPermission() {
        #if SNAPSHOT_HARNESS
        if let debugPermission {
            permissionGranted = debugPermission
            return
        }
        #endif
        permissionGranted = AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func syncHotKey() {
        hotKey.update(
            enabled: preferences.hotKeyEnabled,
            keyCode: preferences.hotKeyCode,
            modifiers: preferences.hotKeyModifiers
        )
    }

    func handleGlobalHotKey() {
        switch phase {
        case .idle:
            refreshPermission()
            guard permissionGranted else { return }
            beginCountdown()
        case .countdown:
            cancelCountdown()
        case .locked, .ending:
            break
        }
    }

    func beginCountdown() {
        guard phase == .idle else { return }
        refreshPermission()
        guard permissionGranted else {
            errorMessage = String(localized: "Grant macOS Accessibility permission first.")
            requestPermission()
            return
        }

        errorMessage = nil
        countdownTask?.cancel()

        let seconds = preferences.countdownSeconds
        if seconds <= 0 {
            startSession()
            return
        }

        countdownTask = Task { [weak self] in
            guard let self else { return }

            for value in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                phase = .countdown(value)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            guard !Task.isCancelled else { return }
            startSession()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        phase = .idle
    }

    private func stopForSafety(message: String) {
        if case .countdown = phase {
            cancelCountdown()
            errorMessage = message
        } else {
            endSession(message: message)
        }
    }

    func endSession(message: String? = nil) {
        guard phase == .locked || phase == .ending else { return }
        phase = .ending

        countdownTask?.cancel()
        sessionTimerTask?.cancel()
        escapeHoldTask?.cancel()
        countdownTask = nil
        sessionTimerTask = nil
        escapeHoldTask = nil

        inputBlocker.stop()
        pointerShieldController.hide()
        blackoutController.hide()
        hudController.close()
        hudModel = nil

        remainingSeconds = 0
        phase = .idle
        if let message {
            errorMessage = message
        }
    }

    func quitApplication() {
        if phase == .locked || phase == .ending {
            endSession()
        } else if case .countdown = phase {
            cancelCountdown()
        }
        NSApplication.shared.terminate(nil)
    }

    private func startSession() {
        let triggers = UnlockTriggers(settings: settings, lockPointer: lockPointer)
        if settings.wordEnabled && triggers.wordKeyCodes == nil {
            phase = .idle
            errorMessage = InputBlockerError.invalidUnlockWord.errorDescription
            return
        }

        let options = LockOptions(
            lockPointer: lockPointer,
            blackoutScreen: blackoutScreen,
            durationSeconds: settings.autoUnlockSeconds,
            triggers: triggers,
            holdSeconds: settings.holdKeySeconds,
            unlockHints: settings.hints(lockPointer: lockPointer)
        )
        activeHoldSeconds = options.holdSeconds

        do {
            try inputBlocker.start(lockPointer: options.lockPointer, triggers: options.triggers)
        } catch {
            phase = .idle
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshPermission()
            return
        }

        guard inputBlocker.isBlocking else {
            inputBlocker.stop()
            phase = .idle
            errorMessage = InputBlockerError.tapEnableFailed.localizedDescription
            return
        }

        remainingSeconds = options.durationSeconds
        phase = .locked

        if options.blackoutScreen {
            blackoutController.show(
                screens: screensToBlackOut(),
                frostyAnimationEnabled: preferences.frostyAnimationEnabled
            )
        }

        if options.lockPointer {
            pointerShieldController.show()
        }

        let hudModel = LockHUDViewModel(
            remainingSeconds: remainingSeconds,
            totalSeconds: options.durationSeconds,
            pointerLocked: options.lockPointer,
            blackoutEnabled: options.blackoutScreen,
            unlockHints: options.unlockHints,
            onUnlock: { [weak self] in
                self?.endSession()
            }
        )
        self.hudModel = hudModel
        hudController.show(
            model: hudModel,
            moveEvery: settings.moveWindowEnabled ? settings.moveWindowSeconds : nil
        )

        startSessionTimer()
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        sessionTimerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && phase == .locked {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled && phase == .locked else { return }

                remainingSeconds = max(0, remainingSeconds - 1)
                hudModel?.remainingSeconds = remainingSeconds

                if remainingSeconds == 0 {
                    endSession()
                    return
                }
            }
        }
    }

    private func handle(signal: InputSignal) {
        guard phase == .locked else { return }

        switch signal {
        case .unlockRequested:
            endSession()

        case .unlockKeyChanged(let isDown):
            if isDown {
                startEscapeHoldIfNeeded()
            } else {
                escapeHoldTask?.cancel()
                escapeHoldTask = nil
            }

        case .tapDisabled:
            endSession(
                message: String(localized: "macOS disabled the input filter. FreezeMac unlocked immediately for safety.")
            )
        }
    }

    private func startEscapeHoldIfNeeded() {
        guard escapeHoldTask == nil else { return }

        escapeHoldTask = Task { [weak self] in
            guard let seconds = self?.activeHoldSeconds else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.endSession()
        }
    }

    /// Selected displays, or every display when "all" is chosen or none of the
    /// selected ones are connected (so the blackout never silently does nothing).
    private func screensToBlackOut() -> [NSScreen] {
        guard !settings.blackoutAllDisplays else { return NSScreen.screens }

        let selected = NSScreen.screens.filter { screen in
            screen.displayID.map(settings.blackoutDisplayIDs.contains) ?? false
        }
        return selected.isEmpty ? NSScreen.screens : selected
    }

    private func observeAppActivation() {
        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermission()
                }
            }
        )
    }

    private func observeDisplayChanges() {
        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.displays = DisplayInfo.current()
                }
            }
        )
    }

    private func observeSafetyNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopForSafety(message: String(localized: "The Mac is going to sleep, so FreezeMac stopped the lock."))
                }
            }
        )

        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopForSafety(message: String(localized: "The user session changed, so FreezeMac stopped the lock."))
                }
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.inputBlocker.stop()
                    self?.pointerShieldController.hide()
                    self?.blackoutController.hide(animated: false)
                    self?.hudController.close()
                }
            }
        )
    }
}
