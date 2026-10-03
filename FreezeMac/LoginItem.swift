import Foundation
import ServiceManagement

/// Manages launch at login status via ServiceManagement (SMAppService.mainApp).
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enable: Bool) {
        errorMessage = nil
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
