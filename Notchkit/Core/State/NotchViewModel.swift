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
        // Motif « alignement » : la page se cale à sa place (HIG, retour haptique sur macOS).
        didSet {
            if selectedPage != oldValue && isExpanded && !skipNextPageHaptic { Haptics.play(.snap) }
            skipNextPageHaptic = false
        }
    }
    /// Changement de page dont le cran haptique a déjà été joué (pendant le balayage au trackpad).
    @ObservationIgnored var skipNextPageHaptic = false
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

    /// Forme noire visible (voir `NotchLayout.showsShape`) : masquée au repos sur une vraie encoche.
    var showsShape: Bool {
        NotchLayout.showsShape(isPhysicalNotch: geometry.isPhysicalNotch, isExpanded: isExpanded,
                               hasCompactContent: hasCompactContent, isHovering: isHovering,
                               hasBubbles: !bubbleModules.isEmpty)
    }

    /// Des fichiers sont glissés au-dessus de l'encoche : elle affiche les zones de dépôt.
    private(set) var isDropMode = false
    /// Zone de dépôt survolée.
    private(set) var hoveredDropZone: DropZone?
    /// L'étagère est-elle disponible (module activé) ? Sinon, seule la zone AirDrop est proposée.
    var isShelfAvailable: Bool { dropZones.contains(.shelf) }
    /// Zones proposées au dépôt de fichiers, de gauche à droite.
    var dropZones: [DropZone] { dropZonesProvider() }
    /// Traite les fichiers déposés (fourni par l'AppDelegate).
    @ObservationIgnored var dropHandler: @MainActor ([URL], DropZone) -> Void = { _, _ in }
    @ObservationIgnored var dropZonesProvider: @MainActor () -> [DropZone] = { [.airDrop] }
    /// Modules qui reçoivent directement un fichier glissé au-dessus de leur page ouverte (ex. Convertisseur),
    /// sans passer par les zones de dépôt.
    @ObservationIgnored var directDropModules: Set<String> = []
    /// Module visé par le glissement en cours (dépôt direct) ; prévenu par `directDropChanged`.
    private(set) var directDropTarget: String? {
        didSet { if directDropTarget != oldValue { directDropChanged(oldValue, directDropTarget) } }
    }
    @ObservationIgnored var directDropChanged: @MainActor (_ old: String?, _ new: String?) -> Void = { _, _ in }
    @ObservationIgnored var directDropHandler: @MainActor ([URL], String) -> Void = { _, _ in }

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
        currentAlert != nil || (!isSettlingAfterCollapse && manager.compactModule != nil && menuLimitedSideWidth != 0)
    }

    /// Repli en cours : l'encoche se referme d'abord jusqu'à sa taille de repos, puis l'activité
    /// compacte ressort, comme quand elle démarre. Les alertes ne sont pas retardées.
    private(set) var isSettlingAfterCollapse = false
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// Dernier repli (voir `NotchLayout.openDelay`).
    @ObservationIgnored private var lastCollapse: Date?

    /// Largeur laissée par les menus de l'app active autour d'une encoche réelle
    /// (voir `MenuBarAvoidance.compactSideWidth`) : `nil` sans contrainte, `0` pour masquer
    /// l'activité compacte. Les alertes passagères (volume…) n'en tiennent pas compte.
    var menuLimitedSideWidth: CGFloat?

    /// Affichage replié façon « Dynamic Island » (module compact qui le demande, sans alerte).
    /// Uniquement pour la pastille flottante : en mode encoche, le contenu doit rester à l'écart
    /// des arrondis qui raccordent l'encoche au bord de l'écran.
    var isIsland: Bool {
        geometry.style == .pill && !isExpanded && currentAlert == nil && manager.compactModule?.compactIsland == true
    }

    /// Activités secondaires affichées en bulles (encoche repliée, sans alerte agrandie).
    var bubbleModules: [any NotchModule] {
        guard !isExpanded, !isSettlingAfterCollapse, !isQuiet, currentAlert?.expandedContent == nil else { return [] }
        return manager.secondaryCompactModules
    }

    /// Mode jeu : l'encoche reste repliée et discrète (pas d'ouverture au survol, ni alertes, ni bulles).
    /// Seuls les gestes explicites (menu, raccourci) peuvent encore la déplier.
    private(set) var isQuiet = false

    func setQuiet(_ quiet: Bool) {
        guard quiet != isQuiet else { return }
        isQuiet = quiet
        guard quiet else { return }
        hoverTask?.cancel()
        bubbleHoverTask?.cancel()
        bubbleMenuRequested = false
        closeBubbleControls()
        if isHovering { withAnimation(.easeOut(duration: 0.18)) { isHovering = false } }
        alertTask?.cancel()
        if currentAlert != nil { withAnimation(NotchLayout.spring) { currentAlert = nil } }
        if !isHeld { collapse() }
    }

    /// Écran verrouillé : seules les activités en cours restent affichées, sans aucune interaction
    /// (ni ouverture, ni gonflement au survol, ni menu des bulles, ni dépôt de fichiers).
    private(set) var isScreenLocked = false

    func setScreenLocked(_ locked: Bool) {
        guard locked != isScreenLocked else { return }
        isScreenLocked = locked
        if locked {
            hoverTask?.cancel()
            bubbleHoverTask?.cancel()
            holdReasons.removeAll()
            bubbleMenuRequested = false
            closeBubbleControls()
            isHovering = false
            if isDropMode {
                isDropMode = false
                hoveredDropZone = nil
            }
            collapse()
        }
    }

    /// Fin contour autour de l'encoche et des bulles, comme la Dynamic Island : quand une activité est
    /// en cours (musique, minuteur, alerte…) et quand l'encoche est dépliée. Au repos, l'encoche
    /// repliée reste une simple découpe noire.
    var showsOutline: Bool { hasCompactContent || isExpanded }

    /// Teinte du contour : celle de l'activité repliée affichée (pas pendant une alerte ni dépliée).
    var keyLineColor: Color? {
        guard !isExpanded, currentAlert == nil else { return nil }
        return manager.compactModule?.keyLineColor
    }

    /// Au moins deux activités secondaires : rangées dans une pile qui se déroule au survol.
    var showsBubbleStack: Bool { bubbleModules.count >= 2 }

    /// Menu des bulles déroulé (souris sur la pile).
    private var bubbleMenuRequested = false
    var isBubbleMenuOpen: Bool { bubbleMenuRequested && showsBubbleStack }

    /// Ouvre ou ferme le menu des bulles (souris sur la pile).
    func setBubbleMenuOpen(_ open: Bool) {
        guard open != bubbleMenuRequested, !(open && isScreenLocked) else { return }
        if !open { closeBubbleControls() }
        withAnimation(NotchLayout.spring) { bubbleMenuRequested = open }
    }

    /// Bulle allongée pour montrer ses commandes (souris dessus).
    private var bubbleControlsRequested: String?
    var bubbleControlsID: String? {
        guard let id = bubbleControlsRequested, bubbleModules.contains(where: { $0.moduleID == id }) else { return nil }
        return id
    }
    @ObservationIgnored private var bubbleControlsTask: Task<Void, Never>?
    /// Parties survolées : la bulle et ses commandes (l'ordre des entrées et sorties n'est pas garanti).
    @ObservationIgnored private var hoveredControlParts: Set<BubbleControlPart> = []

    enum BubbleControlPart: Hashable { case bubble, controls }

    /// Survol d'une bulle qui a des commandes : elles sortent à droite, l'encoche reste repliée.
    func hoverBubbleControls(_ moduleID: String, part: BubbleControlPart, inside: Bool) {
        if inside { hoveredControlParts.insert(part) } else { hoveredControlParts.remove(part) }
        guard !isScreenLocked, !isQuiet else { return }
        let target = hoveredControlParts.isEmpty ? nil : moduleID
        bubbleControlsTask?.cancel()
        guard target != bubbleControlsRequested else { return }
        let delay = target != nil ? NotchLayout.bubbleControlsOpenDelay : NotchLayout.bubbleControlsCloseDelay
        bubbleControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if target != nil { Haptics.play(.step) }
            withAnimation(NotchLayout.spring) { self.bubbleControlsRequested = target }
        }
    }

    private func closeBubbleControls() {
        bubbleControlsTask?.cancel()
        hoveredControlParts.removeAll()
        bubbleControlsRequested = nil
    }

    /// Les bulles sont une zone à part : les survoler n'active pas la grande encoche.
    /// Une bulle survolée assez longtemps ouvre l'encoche sur la page de son activité.
    @ObservationIgnored private var bubbleHoverTask: Task<Void, Never>?

    func hoverBubble(_ moduleID: String, inside: Bool) {
        bubbleHoverTask?.cancel()
        guard !isScreenLocked, !isQuiet else { return }
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
    /// Encoche dépliée : toute la fenêtre lui appartient (les bulles sont masquées) ; repliée,
    /// seulement sa forme (voir `NotchLayout.isPointerInside`).
    func pointerMoved(dx: CGFloat, fromTop: CGFloat) {
        let inside = NotchLayout.isPointerInside(isExpanded: isExpanded, dx: dx, fromTop: fromTop,
                                                 shapeSize: shapeSize, style: geometry.style)
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
        // Mode jeu : pas d'ouverture surprise en pleine partie.
        guard !isQuiet else { return }
        requestedModuleID = moduleID
        expand()
    }

    /// Largeur de chaque côté de l'encoche repliée (une alerte peut demander plus de place).
    var compactSideWidth: CGFloat {
        if let currentAlert { return currentAlert.sideWidth ?? NotchLayout.compactSideWidth }
        let moduleWidth = manager.compactModule?.compactSideWidth ?? NotchLayout.compactSideWidth
        guard let menuLimitedSideWidth, menuLimitedSideWidth > 0 else { return moduleWidth }
        return min(moduleWidth, menuLimitedSideWidth)
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
        var bubbles = NotchLayout.bubblesWidth(count: bubbleModules.count, geometry: geometry, island: isIsland)
        // Commandes sorties d'une bulle : place à droite (et autant à gauche, pour rester centré).
        if let id = bubbleControlsID, let module = manager.module(for: id) { bubbles += module.bubbleControlsWidth }
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
        // Écran verrouillé ou mode jeu : l'encoche ignore la souris.
        guard !isScreenLocked, !isQuiet else { return }
        if isInside != isHovering {
            withAnimation(.easeOut(duration: 0.18)) { isHovering = isInside }
        }
        if !isInside && isHeld { return }
        if isInside && isExpansionBlocked && !isExpanded { return }
        // Survol pendant une alerte liée à un module : l'encoche s'ouvre sur sa page.
        if isInside, !isExpanded, let moduleID = currentAlert?.openModuleID { requestedModuleID = moduleID }
        hoverTask?.cancel()
        let openDelay = NotchLayout.openDelay(base: settings.settings.hoverOpenDelay,
                                              sinceCollapse: lastCollapse.map { Date().timeIntervalSince($0) })
        let delay = isInside ? openDelay : settings.settings.hoverCloseDelay
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
        closeBubbleControls()
        Haptics.play(.tap)
        settleTask?.cancel()
        withAnimation(NotchLayout.spring) {
            isSettlingAfterCollapse = false
            state = .expanded
        }
    }

    func collapse() {
        guard state != .collapsed else { return }
        lastCollapse = Date()
        withAnimation(NotchLayout.spring) {
            isSettlingAfterCollapse = true
            state = .collapsed
        }
        // Une fois l'encoche refermée, l'activité compacte ressort avec le ressort habituel.
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: NotchLayout.collapseSettleDelay)
            guard !Task.isCancelled, let self else { return }
            withAnimation(NotchLayout.spring) { self.isSettlingAfterCollapse = false }
        }
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

    /// Module de la page ouverte qui accepte un dépôt direct, s'il y en a un.
    private var directDropCandidate: String? {
        guard isExpanded, !isDropMode, !directDropModules.isEmpty else { return nil }
        let pages = ModulePage.pages(from: manager)
        guard pages.indices.contains(selectedPage) else { return nil }
        return pages[selectedPage].modules.map(\.id).first(where: directDropModules.contains)
    }

    func fileDragMoved(normalizedX x: CGFloat) {
        guard !isScreenLocked else { return }
        hoverTask?.cancel()
        // Page d'un module qui reçoit les fichiers directement : pas de zones de dépôt.
        if directDropTarget != nil { return }
        if let target = directDropCandidate {
            directDropTarget = target
            Haptics.play(.snap)
            return
        }
        if !isDropMode {
            dropLog.notice("mode dépôt : état \(String(describing: self.state)), écran verrouillé : \(self.isScreenLocked), étagère : \(self.isShelfAvailable)")
            withAnimation(NotchLayout.spring) { isDropMode = true }
            expand()
        }
        let zone = DropZone.zone(atNormalizedX: x, zones: dropZones)
        if zone != hoveredDropZone {
            if hoveredDropZone != nil { Haptics.play(.snap) }
            withAnimation(.snappy(duration: 0.2)) { hoveredDropZone = zone }
        }
    }

    func fileDragEnded() {
        directDropTarget = nil
        guard isDropMode else { return }
        withAnimation(NotchLayout.spring) {
            isDropMode = false
            hoveredDropZone = nil
        }
        if !isMouseInside() { hoverChanged(isInside: false) }
    }

    func dropFiles(_ urls: [URL], normalizedX x: CGFloat) {
        guard !isScreenLocked else { return }
        if let target = directDropTarget {
            directDropTarget = nil
            directDropHandler(urls, target)
            return
        }
        let zone = DropZone.zone(atNormalizedX: x, zones: dropZones)
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
        // Mode jeu : les alertes attendent la fin de la partie (elles ne sont pas rejouées).
        guard !isQuiet else { return }
        alertTask?.cancel()
        // Même alerte déjà affichée (ex. indicateur de volume) : on prolonge seulement sa durée,
        // son contenu se met à jour de lui-même.
        // Pas de vibration : une alerte ne vient pas d'un geste sur le trackpad (HIG : une vibration
        // doit répondre à une action de la personne).
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
