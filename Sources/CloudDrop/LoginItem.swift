import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    private static let defaultAppliedKey = "didApplyDefaultLoginItem"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Launch at Login is on by default: register once, on the very first launch.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultAppliedKey) else { return }
        defaults.set(true, forKey: defaultAppliedKey)
        try? SMAppService.mainApp.register()
    }

    static func toggle() throws {
        if isEnabled {
            try SMAppService.mainApp.unregister()
        } else {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
