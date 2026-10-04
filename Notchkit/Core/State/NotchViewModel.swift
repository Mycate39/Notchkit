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
    /// Indique si la souris est au-dessus du panneau (fourni par le contrôleur de fenêtre).
    @ObservationIgnored var isMouseInside: @MainActor () -> Bool = { false }
    /// Encoche maintenue dépliée (saisie en cours) : la sortie de la souris ne la replie pas.
    @ObservationIgnored private var isHeld = false

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
        if !isInside && isHeld { return }
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

    /// Maintient (ou relâche) l'encoche dépliée. Au relâchement, elle se replie si la souris est ailleurs.
    func setHold(_ hold: Bool) {
        guard hold != isHeld else { return }
        isHeld = hold
        if hold {
            hoverTask?.cancel()
            expand()
        } else if !isMouseInside() {
            hoverChanged(isInside: false)
        }
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
