import AppKit

@MainActor
final class FreezeMacAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindowHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        let prefs = AppPreferences.load()
        if prefs.openMainWindowAtLaunch {
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.async {
                for window in NSApplication.shared.windows where !(window is NSPanel) && window.title == "FreezeMac" {
                    window.close()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let openMainWindowHandler {
                openMainWindowHandler()
            } else {
                for window in NSApplication.shared.windows where !(window is NSPanel) && window.title == "FreezeMac" {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
    }
}
