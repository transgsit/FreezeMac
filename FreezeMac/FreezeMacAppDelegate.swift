import AppKit

@MainActor
final class FreezeMacAppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowCloseObserver: NSObjectProtocol?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      !self.isTerminating,
                      let window = notification.object as? NSWindow,
                      !(window is NSPanel),
                      window.title == "FreezeMac" else { return }

                self.isTerminating = true
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    deinit {
        if let mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(mainWindowCloseObserver)
        }
    }
}
