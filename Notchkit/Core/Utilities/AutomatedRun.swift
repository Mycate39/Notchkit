import Foundation

/// Lancements automatisés (tests unitaires, test de charge, captures DEBUG) : on y évite tout ce qui
/// pourrait déclencher une demande d'autorisation macOS chez l'utilisateur (son, presse-papiers…)
/// ou modifier ses données réelles.
enum AutomatedRun {
    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["NOTCHKIT_STRESS"] != nil
            || environment["NOTCHKIT_SNAPSHOT"] != nil
            || environment["NOTCHKIT_MASCOT_VIDEO"] != nil
            || environment["NOTCHKIT_DEMO"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Tournage de diagnostic (`NOTCHKIT_DIAGNOSTIC`, avec `NOTCHKIT_DEMO`) : l'app se comporte comme
    /// en usage réel là où les lancements automatisés s'en écartent. La capture du son reste active
    /// (l'égaliseur suit les vrais niveaux) et l'encoche est placée dans l'espace SkyLight.
    static var isDiagnostic: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOTCHKIT_DIAGNOSTIC"] != nil
        #else
        false
        #endif
    }

    /// Réglages de l'app : ceux de l'utilisateur, sauf pendant un tournage de démonstration
    /// (`NOTCHKIT_DEMO`), qui travaille sur une copie jetable (`DemoSettings`).
    @MainActor static var settingsDefaults: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHKIT_DEMO"] != nil { return DemoSettings.defaults }
        #endif
        return .standard
    }
}
