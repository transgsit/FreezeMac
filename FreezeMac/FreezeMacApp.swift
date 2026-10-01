import AppKit
import SwiftUI

@main
struct FreezeMacApp: App {
    @NSApplicationDelegateAdaptor(FreezeMacAppDelegate.self) private var appDelegate
    @StateObject private var model = FreezeMacModel()

    var body: some Scene {
        Window("FreezeMac", id: "main") {
            FreezeMacWindowView(model: model)
                .frame(width: 420)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
