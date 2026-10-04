import AppKit
import CoreLocation

/// Position approximative de l'utilisateur (API publique CoreLocation).
///
/// On demande une position ponctuelle, à faible précision (quelques kilomètres suffisent
/// pour la météo), seulement au moment d'actualiser : pas de suivi continu, peu d'énergie.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Appelé quand l'utilisateur accorde ou retire l'autorisation.
    var onAuthorizationChange: (@MainActor () -> Void)?

    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        status == .authorizedAlways
    }

    func requestAuthorization() {
        NSApp.activate()
        manager.requestWhenInUseAuthorization()
    }

    /// Position actuelle, ou `nil` si indisponible ou non autorisée.
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            if pending.count == 1 { manager.requestLocation() }
        }
    }

    /// Nom de la ville correspondant à une position (géocodage inverse d'Apple).
    func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.locality
    }

    private func finish(with location: CLLocation?) {
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: location) }
    }

    // MARK: CLLocationManagerDelegate (appelé sur le thread principal)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated { finish(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(with: nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onAuthorizationChange?() }
    }
}
