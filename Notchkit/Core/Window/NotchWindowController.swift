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
    private var shrinkTask: Task<Void, Never>?

    init(viewModel: NotchViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings

        let hostingView = NotchHostingView(rootView: NotchContainerView(viewModel: viewModel))
        // La vue SwiftUI ne doit pas imposer sa taille à la fenêtre : c'est nous qui la pilotons.
        hostingView.sizingOptions = []
        hostingView.onHoverChange = { [weak viewModel] isInside in
            viewModel?.hoverChanged(isInside: isInside)
        }
        panel.contentView = hostingView
    }

    func show() {
        refreshGeometry()
        setPanelSize(viewModel.panelSize)
        panel.orderFrontRegardless()
        startObserving()
    }

    // MARK: - Observation

    private func startObserving() {
        // Changement d'écran (branchement, résolution, disposition).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }

        // Écran choisi ou simulation d'encoche modifiés dans les réglages.
        trackChanges(of: { [weak self] in
            _ = self?.settings.settings.screenSelection
            _ = self?.settings.settings.simulateNotch
        }, perform: { [weak self] in
            self?.refreshGeometry()
        })

        // Taille de la forme modifiée (survol, alerte, module compact…).
        trackChanges(of: { [weak self] in
            _ = self?.viewModel.panelSize
        }, perform: { [weak self] in
            self?.applyPanelSize()
        })
    }

    // MARK: - Géométrie

    private func refreshGeometry() {
        guard let screen = ScreenLocator.screen(for: settings.settings.screenSelection) else { return }
        viewModel.updateGeometry(ScreenLocator.geometry(for: screen, simulateNotch: settings.settings.simulateNotch))
        // Changement d'écran : on repositionne immédiatement, sans attendre d'animation.
        shrinkTask?.cancel()
        setPanelSize(viewModel.panelSize)
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
    private func setPanelSize(_ size: CGSize) {
        let geometry = viewModel.geometry
        let frame = NSRect(
            x: geometry.centerX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}
