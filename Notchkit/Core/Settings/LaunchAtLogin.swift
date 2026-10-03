import Foundation
import ServiceManagement

/// Lancement automatique à l'ouverture de session (API publique `SMAppService`).
/// L'état est géré par macOS (visible dans Réglages Système > Général > Ouverture).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Active ou désactive le lancement automatique. Renvoie un message d'erreur en cas d'échec.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
