import AppKit
import SwiftUI

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
    /// Affichage sur l'écran de verrouillage (API privée SkyLight, `nil` si indisponible).
    private lazy var lockScreenSpace: LockScreenSpace? = AutomatedRun.isActive ? nil : LockScreenSpace()
    private let hostingView: NotchHostingView<NotchContainerView>
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
        hostingView.onHoverChange = { [weak viewModel] isInside in
            if !isInside { viewModel?.pointerExited() }
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
        startObserving()
        scheduleMenuAvoidance()
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
    }

    private func screenLockChanged(locked: Bool) {
        viewModel.setScreenLocked(locked)
        if locked {
            lockScreenSpace?.moveToLockScreen(panel)
            panel.orderFrontRegardless()
        } else {
            lockScreenSpace?.moveBack(panel)
            reassertOnActiveSpace()
        }
    }

    /// Remet l'encoche à sa place sur le bureau qui vient de s'afficher.
    private func reassertOnActiveSpace() {
        panel.orderFrontRegardless()
        spaceTask?.cancel()
        spaceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.refreshGeometry()
            self.panel.orderFrontRegardless()
            self.updateMenuAvoidance()
        }
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
        // Encoche réelle : macOS place déjà les menus de part et d'autre.
        let hasRealNotch = (screen?.safeAreaInsets.top ?? 0) > 0
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
        let expanded = NotchLayout.panelSize(for: geometry, isExpanded: true, hasCompactContent: true)
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

/// Conteneur dont l'origine est en haut à gauche, pour garder la vue SwiftUI collée en haut.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
