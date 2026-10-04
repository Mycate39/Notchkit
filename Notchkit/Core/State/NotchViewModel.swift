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
    /// Des fichiers sont glissés au-dessus de l'encoche : elle affiche les zones de dépôt.
    private(set) var isDropMode = false
    /// Zone de dépôt survolée.
    private(set) var hoveredDropZone: DropZone?
    /// L'étagère est-elle disponible (module activé) ? Sinon, seule la zone AirDrop est proposée.
    var isShelfAvailable: Bool { dropHandlerAvailability() }
    /// Traite les fichiers déposés (fourni par l'AppDelegate).
    @ObservationIgnored var dropHandler: @MainActor ([URL], DropZone) -> Void = { _, _ in }
    @ObservationIgnored var dropHandlerAvailability: @MainActor () -> Bool = { false }

    @ObservationIgnored let manager: ModuleManager
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    /// Ouvre la fenêtre de réglages (fourni par l'AppDelegate).
    @ObservationIgnored var openSettingsAction: @MainActor (SettingsTab?) -> Void = { _ in }
    /// Indique si la souris est au-dessus du panneau (fourni par le contrôleur de fenêtre).
    @ObservationIgnored var isMouseInside: @MainActor () -> Bool = { false }
    /// Raisons de garder l'encoche dépliée (saisie en cours, menu ouvert…) : tant qu'il y en a,
    /// la sortie de la souris ne la replie pas.
    @ObservationIgnored private var holdReasons: Set<String> = []
    private var isHeld: Bool { !holdReasons.isEmpty }

    init(manager: ModuleManager, settings: SettingsStore) {
        self.manager = manager
        self.settings = settings
    }

    // MARK: - Valeurs dérivées

    var isExpanded: Bool { state == .expanded }

    var hasCompactContent: Bool {
        currentAlert != nil || manager.compactModule != nil
    }

    /// Largeur de chaque côté de l'encoche repliée (une alerte peut demander plus de place).
    var compactSideWidth: CGFloat {
        currentAlert?.sideWidth ?? NotchLayout.compactSideWidth
    }

    var shapeSize: CGSize {
        NotchLayout.shapeSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent,
                              sideWidth: compactSideWidth, alertSize: currentAlert?.expandedSize)
    }

    var panelSize: CGSize {
        NotchLayout.panelSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent,
                              sideWidth: compactSideWidth, alertSize: currentAlert?.expandedSize)
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
    func setHold(_ hold: Bool, reason: String = "saisie") {
        let wasHeld = isHeld
        if hold { holdReasons.insert(reason) } else { holdReasons.remove(reason) }
        if hold {
            hoverTask?.cancel()
            expand()
        } else if wasHeld && !isHeld && !isMouseInside() {
            hoverChanged(isInside: false)
        }
    }

    /// Relâche tous les maintiens (ex. clic en dehors de l'encoche).
    func releaseAllHolds() {
        guard isHeld else { return }
        holdReasons.removeAll()
        if !isMouseInside() { hoverChanged(isInside: false) }
    }

    func toggle() {
        hoverTask?.cancel()
        isExpanded ? collapse() : expand()
    }

    func openSettings(tab: SettingsTab? = nil) {
        holdReasons.removeAll()
        collapse()
        openSettingsAction(tab)
    }

    // MARK: - Glisser-déposer de fichiers

    func fileDragMoved(normalizedX x: CGFloat) {
        hoverTask?.cancel()
        if !isDropMode {
            withAnimation(NotchLayout.spring) { isDropMode = true }
            expand()
        }
        let zone = DropZone.zone(atNormalizedX: x, shelfAvailable: isShelfAvailable)
        if zone != hoveredDropZone {
            withAnimation(.snappy(duration: 0.2)) { hoveredDropZone = zone }
        }
    }

    func fileDragEnded() {
        guard isDropMode else { return }
        withAnimation(NotchLayout.spring) {
            isDropMode = false
            hoveredDropZone = nil
        }
        if !isMouseInside() { hoverChanged(isInside: false) }
    }

    func dropFiles(_ urls: [URL], normalizedX x: CGFloat) {
        let zone = DropZone.zone(atNormalizedX: x, shelfAvailable: isShelfAvailable)
        withAnimation(NotchLayout.spring) {
            isDropMode = false
            hoveredDropZone = nil
        }
        dropHandler(urls, zone)
        collapse()
    }

    // MARK: - Alertes

    /// Retire une alerte avant la fin de sa durée (ex. la demande Touch ID est terminée).
    func dismissAlert(id: UUID) {
        guard currentAlert?.id == id else { return }
        alertTask?.cancel()
        withAnimation(NotchLayout.spring) { currentAlert = nil }
    }

    func present(_ alert: NotchAlert) {
        alertTask?.cancel()
        // Même alerte déjà affichée (ex. indicateur de volume) : on prolonge seulement sa durée,
        // son contenu se met à jour de lui-même.
        if currentAlert?.id != alert.id {
            withAnimation(NotchLayout.spring) { currentAlert = alert }
        }
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: alert.duration)
            guard !Task.isCancelled, let self, self.currentAlert?.id == alert.id else { return }
            withAnimation(NotchLayout.spring) { self.currentAlert = nil }
        }
    }
}
