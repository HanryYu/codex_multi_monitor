import Foundation
import ServiceManagement

enum LoginItemService {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                return SMAppService.mainApp.status == (enabled ? .enabled : .notRegistered)
            } catch {
                print("[CodexMonitor] Failed to update launch-at-login: \(error)")
                return false
            }
        }
        return false
    }
}
