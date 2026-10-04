import Foundation

/// Lancements automatisés (tests unitaires, test de charge, captures DEBUG) : on y évite tout ce qui
/// pourrait déclencher une demande d'autorisation macOS chez l'utilisateur (son, presse-papiers…)
/// ou modifier ses données réelles.
enum AutomatedRun {
    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["NOTCHKIT_STRESS"] != nil
            || environment["NOTCHKIT_SNAPSHOT"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
