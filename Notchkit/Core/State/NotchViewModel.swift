import SwiftUI
import Observation

/// État de l'encoche : replié/déplié, alerte en cours, géométrie de l'écran.
/// C'est la source de vérité pour les vues SwiftUI et pour le contrôleur de fenêtre.
@MainActor
@Observable
final class NotchViewModel {
    enum State: Sendable {
        case collapsed
        case expanded
    }

    private(set) var state: State = .collapsed
    private(set) var geometry: NotchGeometry = .placeholder
    private(set) var currentAlert: NotchAlert?
    /// Page affichée dans l'encoche dépliée (conservée d'une ouverture à l'autre).
    var selectedPage = 0

    @ObservationIgnored let manager: ModuleManager
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    /// Ouvre la fenêtre de réglages (fourni par l'AppDelegate).
    @ObservationIgnored var openSettingsAction: @MainActor () -> Void = {}

    init(manager: ModuleManager, settings: SettingsStore) {
        self.manager = manager
        self.settings = settings
    }

    // MARK: - Valeurs dérivées

    var isExpanded: Bool { state == .expanded }

    var hasCompactContent: Bool {
        currentAlert != nil || manager.compactModule != nil
    }

    var shapeSize: CGSize {
        NotchLayout.shapeSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent)
    }

    var panelSize: CGSize {
        NotchLayout.panelSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent)
    }

    // MARK: - Géométrie

    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
    }

    // MARK: - Survol

    func hoverChanged(isInside: Bool) {
        hoverTask?.cancel()
        let delay = isInside ? settings.settings.hoverOpenDelay : settings.settings.hoverCloseDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if isInside { self?.expand() } else { self?.collapse() }
        }
    }

    // MARK: - Déplier / replier

    func expand() {
        guard state != .expanded else { return }
        withAnimation(NotchLayout.spring) { state = .expanded }
    }

    func collapse() {
        guard state != .collapsed else { return }
        withAnimation(NotchLayout.spring) { state = .collapsed }
    }

    func toggle() {
        hoverTask?.cancel()
        isExpanded ? collapse() : expand()
    }

    func openSettings() {
        collapse()
        openSettingsAction()
    }

    // MARK: - Alertes

    func present(_ alert: NotchAlert) {
        alertTask?.cancel()
        withAnimation(NotchLayout.spring) { currentAlert = alert }
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: alert.duration)
            guard !Task.isCancelled, let self, self.currentAlert?.id == alert.id else { return }
            withAnimation(NotchLayout.spring) { self.currentAlert = nil }
        }
    }
}
