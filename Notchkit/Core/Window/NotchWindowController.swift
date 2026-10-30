import AppKit
import SwiftUI
import os

/// Gère le panneau de l'encoche : position sur l'écran choisi, taille, survol.
///
/// Stratégie de taille : la fenêtre épouse la forme pour que les clics en dehors
/// atteignent normalement les autres apps.
/// - quand la forme grandit, on agrandit la fenêtre tout de suite (invisible car transparente),
///   puis SwiftUI anime la forme ;
/// - quand elle rétrécit, on laisse l'animation se terminer avant de réduire la fenêtre.
@MainActor
final class NotchWindowController {
    private let panel = NotchPanel()
    private let viewModel: NotchViewModel
    private let settings: SettingsStore
    /// Décalage horizontal pour ne pas cacher les menus de l'app active (voir `MenuBarAvoidance`).
    private var menuOffset: CGFloat = 0
    private var menuAvoidanceTask: Task<Void, Never>?
    /// Seconde remise au premier plan après un changement de bureau.
    private var spaceTask: Task<Void, Never>?
    private var shrinkTask: Task<Void, Never>?
    /// Espace au-dessus de tous les bureaux et de l'écran verrouillé (API privée SkyLight, `nil` si indisponible).
    /// Grand lecteur de l'écran verrouillé (fenêtre à part, au milieu de l'écran).
    private lazy var lockScreenMedia = LockScreenMediaWindow(viewModel: viewModel)
    private lazy var lockScreenSpace: LockScreenSpace? =
        AutomatedRun.isActive && !AutomatedRun.isDiagnostic ? nil : LockScreenSpace()
    private let hostingView: NotchHostingView<NotchContainerView>
    /// Reçoit le glisser-déposer à la place de l'encoche quand elle vit dans l'espace SkyLight.
    private var dropCatcher: DropCatcher?
    /// Encoche masquée pendant le plein écran (réglage).
    private var fullScreenHiding: FullScreenHiding?
    private var isHiddenForFullScreen = false
    private let container = FlippedView()

    init(viewModel: NotchViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings

        hostingView = NotchHostingView(rootView: NotchContainerView(viewModel: viewModel))
        // La vue SwiftUI ne doit pas imposer sa taille à la fenêtre : c'est nous qui la pilotons.
        hostingView.sizingOptions = []
        // On ignore la zone de sécurité (barre des menus, encoche) : la forme doit coller au bord.
        hostingView.safeAreaRegions = []
        // Entrée : décidée par la position (grande encoche ou bulles). Sortie : toujours transmise.
        hostingView.onHoverChange = { [weak viewModel, weak panel] isInside in
            // Sortie annoncée alors que le pointeur est encore sur la fenêtre (fin d'un glisser-déposer) :
            // ignorée, sinon l'encoche rouverte sur le convertisseur après un dépôt se refermait seule.
            guard !isInside, panel.map({ !$0.frame.contains(NSEvent.mouseLocation) }) ?? true else { return }
            viewModel?.pointerExited()
        }
        hostingView.onPointerMove = { [weak viewModel] dx, fromTop in
            viewModel?.pointerMoved(dx: dx, fromTop: fromTop)
        }
        hostingView.onFileDrag = { [weak viewModel] x in
            if let x { viewModel?.fileDragMoved(normalizedX: x) } else { viewModel?.fileDragEnded() }
        }
        hostingView.onFileDrop = { [weak viewModel] urls, x in
            viewModel?.dropFiles(urls, normalizedX: x)
        }
        viewModel.isMouseInside = { [weak panel] in
            panel.map { $0.frame.contains(NSEvent.mouseLocation) } ?? false
        }

        // La vue SwiftUI est placée dans un conteneur AppKit simple (redimensionnement automatique,
        // sans Auto Layout) plutôt que d'être directement la `contentView`.
        // Sinon, dans une fenêtre qui contient si peu de vues, les mises à jour de SwiftUI pendant
        // l'animation déclenchent une boucle de contraintes et AppKit fait planter l'app
        // (exception « _postWindowNeedsUpdateConstraints »).
        //
        // La vue SwiftUI garde une taille FIXE (celle de l'encoche dépliée), ancrée en haut au centre :
        // seule la fenêtre change de taille autour d'elle. Ainsi SwiftUI ne recalcule rien quand la
        // fenêtre s'agrandit, et le contenu ne « tombe » pas vers le bas pendant une image
        // (macOS ancre le contenu des fenêtres en bas à gauche lors d'un redimensionnement).
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        // Marges gauche/droite flexibles (reste centrée), marge basse flexible (reste collée en haut,
        // le conteneur étant « retourné » : son origine est en haut à gauche).
        hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        container.addSubview(hostingView)
        panel.contentView = container
    }

    func show() {
        refreshGeometry()
        setPanelSize(viewModel.panelSize)
        panel.orderFrontRegardless()
        // L'encoche ne suit plus les transitions entre bureaux : ni disparition, ni redimensionnement.
        lockScreenSpace?.pin(panel)
        if lockScreenSpace != nil {
            let catcher = DropCatcher(forwardingTo: hostingView)
            // Pendant un glisser, le contenu de l'encoche passe dans la fenêtre de réception (bureau ordinaire) :
            // dans l'espace SkyLight, l'encoche cacherait l'image du fichier glissé.
            catcher.onDragStart = { [weak self] in
                guard let self, !self.viewModel.isScreenLocked else { return }
                self.panel.contentView = NSView()
                self.dropCatcher?.host(self.container)
            }
            catcher.onDragEnd = { [weak self] in
                guard let self, self.panel.contentView !== self.container else { return }
                self.container.removeFromSuperview()
                self.panel.contentView = self.container
            }
            catcher.start(frame: panel.frame)
            dropCatcher = catcher
        }
        startObserving()
        #if DEBUG
        if AutomatedRun.isDiagnostic {
            // Diagnostic des bureaux : visibilité de la fenêtre et changements de bureau, horodatés.
            let start = Date()
            let diag: @Sendable (String) -> Void = { text in
                FileHandle.standardError.write(Data(String(format: "DEMO-DIAG %.2f %@\n", Date().timeIntervalSince(start), text).utf8))
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    diag("fenêtre \(self?.panel.occlusionState.contains(.visible) == true ? "visible" : "masquée")")
                }
            }
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                              object: nil, queue: .main) { _ in diag("changement de bureau") }
        }
        #endif
        scheduleMenuAvoidance()
        let hiding = FullScreenHiding(
            isEnabled: { [weak self] in self?.settings.settings.hidesInFullScreen ?? false },
            screen: { [weak self] in self.flatMap { ScreenLocator.screen(for: $0.settings.settings.screenSelection) } },
            onChange: { [weak self] hidden in self?.setHiddenForFullScreen(hidden) }
        )
        hiding.start()
        fullScreenHiding = hiding
    }

    #if DEBUG
    /// Tournage de démonstration : fenêtre de l'encoche (pour l'enregistrer) et masquage en plein écran
    /// déclenché à la demande.
    var debugPanel: NSWindow { panel }

    func debugSetHiddenForFullScreen(_ hidden: Bool) {
        setHiddenForFullScreen(hidden)
    }
    #endif

    /// Plein écran : l'encoche s'efface et laisse passer la souris, puis revient en sortie.
    private func setHiddenForFullScreen(_ hidden: Bool) {
        if hidden { viewModel.collapse() }
        isHiddenForFullScreen = hidden
        updateFullScreenVisibility()
    }

    /// Encoche masquée en plein écran, sauf le temps d'une alerte qui doit rester visible (volume,
    /// luminosité) ; elle laisse toujours passer la souris.
    private func updateFullScreenVisibility() {
        let visible = !isHiddenForFullScreen || viewModel.currentAlert?.showsInFullScreen == true
        panel.ignoresMouseEvents = isHiddenForFullScreen
        guard panel.alphaValue != (visible ? 1 : 0) else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible && isHiddenForFullScreen ? 0.15 : 0.25
            panel.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: - Observation

    private func startObserving() {
        // Clic en dehors de l'encoche pendant une saisie : on relâche le maintien.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewModel.releaseAllHolds() }
        }

        // Menu (clic droit sur un widget) ouvert depuis l'encoche dépliée : elle reste ouverte.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.viewModel.isExpanded else { return }
                self.viewModel.setHold(true, reason: "menu")
            }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewModel.setHold(false, reason: "menu") }
        }

        // Changement d'écran (branchement, résolution, disposition).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }

        // Changement de bureau (Spaces) : en quittant une app en plein écran, macOS peut retirer
        // le panneau pendant la transition. On le remet au premier plan aussitôt, puis une fois
        // l'animation de macOS terminée (position recalculée : la barre des menus peut différer).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassertOnActiveSpace() }
        }

        // Écran verrouillé / déverrouillé : l'encoche reste visible par-dessus le verrouillage.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLockChanged(locked: true) }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLockChanged(locked: false) }
        }

        // App au premier plan changée : ses menus n'ont pas la même largeur.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleMenuAvoidance() }
        }

        // Écran choisi, simulation d'encoche ou apparence modifiés dans les réglages.
        trackChanges(of: { [weak self] in
            _ = self?.settings.settings.screenSelection
            _ = self?.settings.settings.simulateNotch
            _ = self?.viewModel.appearance
            _ = self?.settings.settings.avoidAppMenus
        }, perform: { [weak self] in
            self?.refreshGeometry()
            self?.scheduleMenuAvoidance()
        })

        // Taille de la forme modifiée (survol, alerte, module compact…).
        trackChanges(of: { [weak self] in
            _ = self?.viewModel.panelSize
        }, perform: { [weak self] in
            self?.applyPanelSize()
        })

        // Plein écran : l'indicateur de volume et de luminosité apparaît quand même.
        trackChanges(of: { [weak self] in
            _ = self?.viewModel.currentAlert?.id
        }, perform: { [weak self] in
            guard let self, self.isHiddenForFullScreen else { return }
            self.updateFullScreenVisibility()
        })

        // Grand lecteur de l'écran verrouillé : affiché tant que le Mac est verrouillé et qu'un module en propose un.
        trackChanges(of: { [weak self] in
            _ = self?.viewModel.lockScreenMediaModule?.moduleID
        }, perform: { [weak self] in
            self?.updateLockScreenMedia()
        })
    }

    private func updateLockScreenMedia() {
        lockScreenMedia.update(screen: ScreenLocator.screen(for: settings.settings.screenSelection),
                               level: panel.level, space: lockScreenSpace)
    }

    private func screenLockChanged(locked: Bool) {
        Logger(subsystem: "com.andeolchenaux.notchkit", category: "espace")
            .notice("écran \(locked ? "verrouillé" : "déverrouillé") · espace SkyLight \(self.lockScreenSpace != nil ? "disponible" : "indisponible") · fenêtre visible \(self.panel.isVisible)")
        viewModel.setScreenLocked(locked)
        // Le panneau est déjà dans l'espace au-dessus de l'écran verrouillé : on le remet seulement devant.
        if locked {
            lockScreenSpace?.pin(panel)
            panel.level = NotchPanel.lockedLevel
            panel.orderFrontRegardless()
        } else {
            panel.level = NotchPanel.normalLevel
            reassertOnActiveSpace()
        }
        updateLockScreenMedia()
    }

    /// Remet l'encoche à sa place sur le bureau qui vient de s'afficher.
    ///
    /// Dans l'espace SkyLight, le panneau reste affiché et immobile pendant la transition : le remettre
    /// devant ou le replacer à ce moment-là casse l'animation en cours (encoche décalée pendant près
    /// d'une seconde, ouverture sans animation). On ne le fait donc que s'il a disparu, et on ne le
    /// replace que si la géométrie de l'écran a changé.
    private func reassertOnActiveSpace() {
        viewModel.spaceDidChange()
        let needsFront = { [weak self] in
            guard let self else { return false }
            return self.lockScreenSpace == nil || !self.panel.isVisible
        }
        if needsFront() { panel.orderFrontRegardless() }
        spaceTask?.cancel()
        spaceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            if self.lockScreenSpace == nil || self.screenGeometryChanged { self.refreshGeometry() }
            if needsFront() { self.panel.orderFrontRegardless() }
            self.updateMenuAvoidance()
        }
    }

    /// Vrai si l'écran de l'encoche n'a plus la géométrie connue (barre des menus, écran, résolution).
    private var screenGeometryChanged: Bool {
        guard let screen = ScreenLocator.screen(for: settings.settings.screenSelection) else { return false }
        return ScreenLocator.geometry(for: screen, simulateNotch: settings.settings.simulateNotch) != viewModel.geometry
    }

    // MARK: - Menus de l'app active

    /// Les menus d'une app qui vient de s'activer sont posés un instant plus tard : on attend un peu.
    private func scheduleMenuAvoidance() {
        menuAvoidanceTask?.cancel()
        menuAvoidanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.updateMenuAvoidance()
        }
    }

    private func updateMenuAvoidance() {
        let geometry = viewModel.geometry
        let screen = ScreenLocator.screen(for: settings.settings.screenSelection)
        // Encoche réelle : macOS place les menus de part et d'autre de l'encoche physique, mais
        // l'activité compacte la déborde ; on la rétrécit (ou la masque) au lieu de la décaler.
        let hasRealNotch = (screen?.safeAreaInsets.top ?? 0) > 0
        var sideWidth: CGFloat?
        if settings.settings.avoidAppMenus, hasRealNotch, !AutomatedRun.isActive {
            let notchMinX = geometry.centerX - geometry.screenFrame.minX - geometry.closedSize.width / 2
            sideWidth = MenuBarAvoidance.compactSideWidth(
                menuSpans: MenuBarAvoidance.frontmostMenuSpans(),
                notchMinX: notchMinX, notchMaxX: notchMinX + geometry.closedSize.width,
                preferred: NotchLayout.compactSideWidth
            )
        }
        if viewModel.menuLimitedSideWidth != sideWidth { viewModel.menuLimitedSideWidth = sideWidth }

        var offset: CGFloat = 0
        if settings.settings.avoidAppMenus, !hasRealNotch, !AutomatedRun.isActive {
            let normal = NotchLayout.shapeSize(for: geometry, isExpanded: false, hasCompactContent: true)
            let island = NotchLayout.shapeSize(for: geometry, isExpanded: false, hasCompactContent: true, island: true)
            offset = MenuBarAvoidance.offset(
                menusRightEdge: MenuBarAvoidance.frontmostMenusRightEdge(),
                centerX: geometry.centerX - geometry.screenFrame.minX,
                halfWidth: max(normal.width, island.width) / 2  // les bulles sont à droite : sans effet sur les menus
            )
        }
        guard offset != menuOffset else { return }
        menuOffset = offset
        setPanelSize(panel.frame.size, animated: true)
    }

    // MARK: - Géométrie

    private func refreshGeometry() {
        guard let screen = ScreenLocator.screen(for: settings.settings.screenSelection) else { return }
        viewModel.updateGeometry(ScreenLocator.geometry(for: screen, simulateNotch: settings.settings.simulateNotch))
        // Changement d'écran : on repositionne immédiatement, sans attendre d'animation.
        shrinkTask?.cancel()
        setPanelSize(viewModel.panelSize)
    }

    /// Donne à la vue SwiftUI la plus grande taille possible de l'encoche, centrée en haut.
    private func layoutHostingView() {
        let geometry = viewModel.geometry
        let expanded = NotchLayout.panelSize(for: geometry, isExpanded: true, hasCompactContent: true,
                                             pageSize: NotchLayout.maxExpandedSize)
        let compact = NotchLayout.panelSize(for: geometry, isExpanded: false, hasCompactContent: true)
        // Plus la marge réservée à l'ombre de l'encoche dépliée.
        let margin = NotchLayout.expandedShadowMargin
        let size = CGSize(width: max(expanded.width, compact.width) + margin * 2,
                          height: max(expanded.height, compact.height) + margin)
        let bounds = container.bounds
        hostingView.frame = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    private func applyPanelSize() {
        let target = viewModel.panelSize
        let current = panel.frame.size
        shrinkTask?.cancel()

        // On agrandit immédiatement ce qui doit grandir…
        let grown = CGSize(width: max(target.width, current.width), height: max(target.height, current.height))
        if grown != current { setPanelSize(grown) }

        // … et on réduit après l'animation ce qui doit rétrécir.
        guard grown != target else { return }
        shrinkTask = Task { [weak self] in
            try? await Task.sleep(for: NotchLayout.shrinkDelay)
            guard !Task.isCancelled, let self else { return }
            self.setPanelSize(self.viewModel.panelSize)
        }
    }

    /// Place la fenêtre collée en haut de l'écran, centrée sur l'encoche.
    private func setPanelSize(_ size: CGSize, animated: Bool = false) {
        let geometry = viewModel.geometry
        let frame = NSRect(
            x: geometry.centerX + menuOffset - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        dropCatcher?.follow(frame)
        if animated {
            // Glissement doux quand l'encoche s'écarte des menus.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
            return
        }
        // Pas d'affichage intermédiaire : on replace d'abord la vue SwiftUI, puis le système redessine.
        panel.setFrame(frame, display: false)
        layoutHostingView()
    }
}

// MARK: - Diagnostic

extension NotchWindowController {
    /// Rapport texte (écrans, détection de l'encoche, fenêtre) à copier pour signaler un problème.
    func diagnosticReport() -> String {
        var lines: [String] = []
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var model = [CChar](repeating: 0, count: 64)
        var size = model.count
        sysctlbyname("hw.model", &model, &size, nil, 0)
        lines.append("Notchkit \(version) (\(build)) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let modelName = String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        lines.append("Mac : \(modelName) · Accessibilité : \(AXIsProcessTrusted())")
        for (index, screen) in NSScreen.screens.enumerated() {
            lines.append("Écran \(index) : frame \(screen.frame) · visible \(screen.visibleFrame) · échelle \(screen.backingScaleFactor)")
            lines.append("  safeArea.top \(screen.safeAreaInsets.top) · gauche \(screen.auxiliaryTopLeftArea.map { "\($0)" } ?? "-") · droite \(screen.auxiliaryTopRightArea.map { "\($0)" } ?? "-")")
        }
        let geometry = viewModel.geometry
        lines.append("Géométrie : \(geometry.style) · fermée \(geometry.closedSize) · centreX \(geometry.centerX) · écran \(geometry.screenFrame)")
        lines.append("Fenêtre : \(panel.frame) · visible \(panel.isVisible) · espace actif \(panel.isOnActiveSpace) · occlusion \(panel.occlusionState.contains(.visible) ? "visible" : "cachée") · niveau \(panel.level.rawValue) · alpha \(panel.alphaValue)")
        lines.append("État : déplié \(viewModel.isExpanded) · écran verrouillé \(viewModel.isScreenLocked) · décalage menus \(menuOffset)")
        lines.append("Réglages : écran \(settings.settings.screenSelection) · simuler \(settings.settings.simulateNotch)")
        return lines.joined(separator: "\n")
    }
}

/// Conteneur dont l'origine est en haut à gauche, pour garder la vue SwiftUI collée en haut.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
