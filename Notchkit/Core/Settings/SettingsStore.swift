import Foundation
import Observation

/// Stockage local des réglages (UserDefaults).
/// Toute modification de `settings` est sauvegardée immédiatement.
@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet {
            if settings != oldValue { save() }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "notchkit.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
