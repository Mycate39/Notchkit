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
        ScreenshotsModule.self,
        TogglesModule.self,
        CameraModule.self,
        DayProgressModule.self,
        NotesModule.self,
        TodoModule.self,
        SystemMonitorModule.self,
        DashboardModule.self,
        ScreenTimeModule.self,
        HealthModule.self,
        TranslationModule.self,
        GitModule.self,
        AirPodsModule.self,
        LiveActivitiesModule.self,
        ClipboardModule.self,
        SystemHUDModule.self,
        UnlockModule.self,
        VideoDownloadModule.self,
        // Assistant IA mis de côté pour l'instant (le code reste dans Modules/Assistant) :
        // remettre `AssistantModule.self` ici pour le réactiver.
    ]
}
