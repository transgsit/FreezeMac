import AppKit
import SwiftUI

@main
struct FreezeMacApp: App {
    @NSApplicationDelegateAdaptor(FreezeMacAppDelegate.self) private var appDelegate
    @StateObject private var model = FreezeMacModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("FreezeMac", id: "main") {
            FreezeMacWindowView(model: model)
                .frame(width: 420)
                .onAppear {
                    appDelegate.openMainWindowHandler = {
                        openMainWindow()
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "Quit FreezeMac")) {
                    model.quitApplication()
                }
                .keyboardShortcut("q")
            }
        }

        MenuBarExtra {
            MenuBarView(model: model, openMainWindow: {
                openMainWindow()
            })
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.phase.isBusy ? "lock.fill" : "snowflake")
                if model.phase.isBusy && model.preferences.showRemainingTimeInMenuBar && model.remainingSeconds > 0 {
                    Text(model.formattedRemainingTime)
                }
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
