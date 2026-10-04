import Foundation

/// Liste de tous les modules connus de l'application.
/// Pour ajouter un module : créer sa classe dans `Modules/` puis l'ajouter ici.
enum ModuleRegistry {
    @MainActor
    static let allModules: [any NotchModule.Type] = [
        MusicModule.self,
        ClockModule.self,
        BatteryModule.self,
        CalendarModule.self,
        WeatherModule.self,
        ClaudeModule.self,
        ShelfModule.self,
    ]
}
