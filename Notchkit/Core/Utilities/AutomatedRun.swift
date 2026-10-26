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

    /// Réglages de l'app : ceux de l'utilisateur, sauf pendant un tournage de démonstration
    /// (`NOTCHKIT_DEMO`), qui travaille sur une copie jetable (`DemoSettings`).
    @MainActor static var settingsDefaults: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHKIT_DEMO"] != nil { return DemoSettings.defaults }
        #endif
        return .standard
    }
}
