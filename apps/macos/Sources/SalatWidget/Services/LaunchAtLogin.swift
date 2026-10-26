import Foundation
import OSLog
import ServiceManagement

/// Thin wrapper over `SMAppService` for the "Open at login" preference.
enum LaunchAtLogin {
    /// Login items only work for a proper `.app` bundle (not `swift run`).
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.app.error("Couldn't update login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
