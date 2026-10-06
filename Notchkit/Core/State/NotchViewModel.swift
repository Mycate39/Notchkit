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
    var selectedPage = 0 {
        didSet { if selectedPage != oldValue && isExpanded { Haptics.play(.step) } }
    }
    /// Apparence en vigueur (observée : tailles et couleurs se mettent à jour à chaque changement).
    private(set) var appearance = NotchAppearance()

    func applyAppearance(_ new: NotchAppearance) {
        guard new != appearance else { return }
        NotchLayout.appearance = new
        withAnimation(NotchLayout.spring) { appearance = new }
    }
    /// Souris au-dessus de l'encoche (pour l'ombre de survol, avant l'ouverture).
    private(set) var isHovering = false

    /// Petite ombre sous l'encoche repliée quand la souris la survole.
    var showsHoverShadow: Bool { isHovering && !isExpanded }

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

    /// Affichage replié façon « Dynamic Island » (module compact qui le demande, sans alerte).
    /// Uniquement pour la pastille flottante : en mode encoche, le contenu doit rester à l'écart
    /// des arrondis qui raccordent l'encoche au bord de l'écran.
    var isIsland: Bool {
        geometry.style == .pill && !isExpanded && currentAlert == nil && manager.compactModule?.compactIsland == true
    }

    /// Activités secondaires affichées en bulles (encoche repliée, sans alerte agrandie).
    var bubbleModules: [any NotchModule] {
        guard !isExpanded, currentAlert?.expandedContent == nil else { return [] }
        return manager.secondaryCompactModules
    }

    /// Écran verrouillé : l'encoche reste affichée (activités en cours) mais ne s'ouvre plus.
    private(set) var isScreenLocked = false

    func setScreenLocked(_ locked: Bool) {
        guard locked != isScreenLocked else { return }
        isScreenLocked = locked
        if locked {
            hoverTask?.cancel()
            bubbleHoverTask?.cancel()
            holdReasons.removeAll()
            bubbleMenuRequested = false
            collapse()
        }
    }

    /// Fin contour autour de l'encoche et des bulles, comme la Dynamic Island : quand une activité est
    /// en cours (musique, minuteur, alerte…) et quand l'encoche est dépliée. Au repos, l'encoche
    /// repliée reste une simple découpe noire.
    var showsOutline: Bool { hasCompactContent || isExpanded }

    /// Au moins deux activités secondaires : rangées dans une pile qui se déroule au survol.
    var showsBubbleStack: Bool { bubbleModules.count >= 2 }

    /// Menu des bulles déroulé (souris sur la pile).
    private var bubbleMenuRequested = false
    var isBubbleMenuOpen: Bool { bubbleMenuRequested && showsBubbleStack }

    /// Ouvre ou ferme le menu des bulles (souris sur la pile).
    func setBubbleMenuOpen(_ open: Bool) {
        guard open != bubbleMenuRequested else { return }
        withAnimation(NotchLayout.spring) { bubbleMenuRequested = open }
    }

    /// Les bulles sont une zone à part : les survoler n'active pas la grande encoche.
    /// Une bulle survolée assez longtemps ouvre l'encoche sur la page de son activité.
    @ObservationIgnored private var bubbleHoverTask: Task<Void, Never>?

    func hoverBubble(_ moduleID: String, inside: Bool) {
        bubbleHoverTask?.cancel()
        if inside {
            requestedModuleID = moduleID
            let delay = settings.settings.hoverOpenDelay
            bubbleHoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.expand()
            }
        } else if !isExpanded, requestedModuleID == moduleID {
            requestedModuleID = nil
        }
    }

    // MARK: - Zones de la fenêtre

    /// Souris au-dessus de la grande encoche (et non des bulles, dans la même fenêtre).
    @ObservationIgnored private(set) var isPointerOverNotch = false

    /// La grande encoche occupe le centre de la fenêtre ; les bulles sont à droite.
    /// Encoche dépliée : toute la fenêtre lui appartient (les bulles sont masquées).
    func pointerMoved(dx: CGFloat, fromTop: CGFloat) {
        let inside = isExpanded || bubbleModules.isEmpty
            || NotchLayout.isOverNotch(dx: dx, fromTop: fromTop, shapeSize: shapeSize, style: geometry.style)
        guard inside != isPointerOverNotch else { return }
        isPointerOverNotch = inside
        hoverChanged(isInside: inside)
    }

    func pointerExited() {
        isPointerOverNotch = false
        hoverChanged(isInside: false)
    }

    /// Module à montrer à l'ouverture (bulle cliquée).
    @ObservationIgnored var requestedModuleID: String?

    /// Ouvre l'encoche sur la page d'un module (clic sur une bulle).
    func expand(showing moduleID: String) {
        requestedModuleID = moduleID
        expand()
    }

    /// Largeur de chaque côté de l'encoche repliée (une alerte peut demander plus de place).
    var compactSideWidth: CGFloat {
        currentAlert?.sideWidth ?? NotchLayout.compactSideWidth
    }

    var shapeSize: CGSize {
        _ = appearance  // dépend de la taille choisie
        return NotchLayout.shapeSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent,
                              sideWidth: compactSideWidth, alertSize: currentAlert?.expandedSize,
                              island: isIsland)
    }

    var panelSize: CGSize {
        _ = appearance
        let size = NotchLayout.panelSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent,
                              sideWidth: compactSideWidth, alertSize: currentAlert?.expandedSize,
                              island: isIsland)
        // Place autour de la forme pour que l'ombre (survol ou encoche dépliée) ne soit pas coupée.
        // Bulles à droite : la fenêtre s'élargit des deux côtés pour garder l'encoche centrée.
        let bubbles = NotchLayout.bubblesWidth(count: bubbleModules.count, geometry: geometry, island: isIsland)
        let margin = isExpanded ? NotchLayout.expandedShadowMargin : (showsHoverShadow ? NotchLayout.hoverShadowMargin : 0)
        guard margin > 0 || bubbles > 0 else { return size }
        var height = size.height + margin
        // Menu déroulé : la fenêtre descend pour contenir la colonne de bulles.
        if isBubbleMenuOpen {
            let menu = NotchLayout.bubbleMenuHeight(count: bubbleModules.count, geometry: geometry, island: isIsland)
            height = max(height, NotchLayout.topInset(for: geometry.style) + menu + NotchLayout.hoverShadowMargin)
        }
        return CGSize(width: size.width + (margin + bubbles) * 2, height: height)
    }

    // MARK: - Géométrie

    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
    }

    // MARK: - Survol

    /// Ouverture au survol bloquée (souris sur un bouton cliquable de l'encoche repliée).
    @ObservationIgnored private var isExpansionBlocked = false

    func setExpansionBlocked(_ blocked: Bool) {
        isExpansionBlocked = blocked
        if blocked {
            if !isExpanded { hoverTask?.cancel() }
        } else if isPointerOverNotch && !isExpanded {
            hoverChanged(isInside: true)
        }
    }

    func hoverChanged(isInside: Bool) {
        if isInside != isHovering {
            withAnimation(.easeOut(duration: 0.18)) { isHovering = isInside }
        }
        if !isInside && isHeld { return }
        if isInside && isExpansionBlocked && !isExpanded { return }
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
        // Écran verrouillé : seules les activités repliées sont visibles, rien ne se déplie.
        guard state != .expanded, !isScreenLocked else { return }
        // Le menu des bulles se referme : l'encoche dépliée prend le relais.
        bubbleMenuRequested = false
        bubbleHoverTask?.cancel()
        Haptics.play(.tap)
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
            if hoveredDropZone != nil { Haptics.play(.snap) }
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
            Haptics.play(.tap)
            withAnimation(NotchLayout.spring) { currentAlert = alert }
        }
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: alert.duration)
            guard !Task.isCancelled, let self, self.currentAlert?.id == alert.id else { return }
            withAnimation(NotchLayout.spring) { self.currentAlert = nil }
        }
    }
}
