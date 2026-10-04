import AppKit
import CoreLocation
import SwiftUI
import Observation

/// Module Météo : conditions actuelles, minimales/maximales du jour et prochaines heures.
///
/// Position automatique (CoreLocation, autorisation demandée depuis la carte) avec repli
/// sur une ville choisie dans les réglages. Actualisation toutes les 30 minutes et au réveil.
@MainActor
@Observable
final class WeatherModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "weather",
        name: "Météo",
        summary: "Conditions actuelles et prévisions des prochaines heures (Open-Meteo).",
        systemImage: "cloud.sun",
        category: .widgets,
        tier: .free,
        defaultEnabled: true
    )

    enum LocationMode: String, CaseIterable, Identifiable {
        case automatic
        case manual
        var id: String { rawValue }
    }

    enum Status: Equatable {
        case idle
        case loading
        /// Aucune position utilisable : autorisation à demander ou ville à choisir.
        case needsLocation
        case failed
    }

    private(set) var snapshot: WeatherSnapshot?
    private(set) var status: Status = .idle
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: Réglages du module

    var locationMode: LocationMode {
        didSet {
            UserDefaults.standard.set(locationMode.rawValue, forKey: Keys.locationMode)
            refreshNow()
        }
    }
    var manualPlace: WeatherPlace? {
        didSet {
            UserDefaults.standard.set(manualPlace.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.manualPlace)
            refreshNow()
        }
    }
    /// Affiche la température quand l'encoche est repliée.
    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }

    private enum Keys {
        static let locationMode = "module.weather.locationMode"
        static let manualPlace = "module.weather.manualPlace"
        static let showInCompact = "module.weather.showInCompact"
    }

    static let refreshInterval: Duration = .seconds(30 * 60)

    @ObservationIgnored let context: ModuleContext
    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var isStarted = false

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        locationMode = defaults.string(forKey: Keys.locationMode).flatMap(LocationMode.init) ?? .automatic
        manualPlace = defaults.data(forKey: Keys.manualPlace).flatMap { try? JSONDecoder().decode(WeatherPlace.self, from: $0) }
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? false
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true
        locationStatus = location.status

        location.onAuthorizationChange = { [weak self] in
            guard let self else { return }
            self.locationStatus = self.location.status
            self.refreshNow()
        }

        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }

        // Au réveil, on actualise si les données ont plus de 15 minutes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let age = self.snapshot.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity
                if age > 15 * 60 { self.refreshNow() }
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        refreshLoop?.cancel()
        refreshLoop = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        location.onAuthorizationChange = nil
    }

    // MARK: Actions

    func refreshNow() {
        guard isStarted else { return }
        Task { await refresh() }
    }

    func requestLocationAccess() {
        location.requestAuthorization()
    }

    func openSettings() {
        context.openSettings()
    }

    // MARK: Actualisation

    private func refresh() async {
        guard isStarted, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let target = await resolveLocation() else {
            status = .needsLocation
            return
        }

        if snapshot == nil { status = .loading }
        do {
            var newSnapshot = try await OpenMeteoClient.forecast(latitude: target.latitude, longitude: target.longitude)
            newSnapshot.locationName = target.name
            snapshot = newSnapshot
            status = .idle
        } catch {
            // On garde l'ancienne météo affichée si on en a une.
            status = snapshot == nil ? .failed : .idle
        }
    }

    /// Position à utiliser : automatique si autorisée, sinon la ville choisie.
    private func resolveLocation() async -> (latitude: Double, longitude: Double, name: String?)? {
        if locationMode == .automatic, location.isAuthorized,
           let current = await location.currentLocation() {
            let name = await location.placeName(for: current)
            return (current.coordinate.latitude, current.coordinate.longitude, name)
        }
        if let manualPlace {
            return (manualPlace.latitude, manualPlace.longitude, manualPlace.name)
        }
        return nil
    }

    // MARK: Affichage

    var compactPriority: ModulePriority {
        showInCompact && snapshot != nil ? .low : .none
    }

    var expandedWidthWeight: CGFloat { 1.5 }

    func compactLeading() -> AnyView? {
        guard let snapshot else { return nil }
        return AnyView(
            Image(systemName: WeatherCondition.symbol(code: snapshot.code, isDay: snapshot.isDay))
                .symbolRenderingMode(.multicolor)
        )
    }

    func compactTrailing() -> AnyView? {
        guard let snapshot else { return nil }
        return AnyView(Text(TemperatureFormat.string(snapshot.temperature)).monospacedDigit())
    }

    func miniView() -> AnyView {
        guard let snapshot else { return AnyView(MiniWidget(symbol: "cloud.sun", value: "–", caption: nil)) }
        return AnyView(
            MiniWidget(value: TemperatureFormat.string(snapshot.temperature), caption: snapshot.locationName) {
                Image(systemName: WeatherCondition.symbol(code: snapshot.code, isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 24))
            }
        )
    }

    func expandedView() -> AnyView {
        AnyView(WeatherExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(WeatherSettingsView(module: self))
    }
}
