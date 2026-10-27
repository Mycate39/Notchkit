import AppKit
import SwiftUI

/// Fenêtre du grand lecteur de l'écran verrouillé (`NotchModule.lockScreenMedia`), au milieu de l'écran
/// de l'encoche, sous l'heure de macOS. Même traitement que l'encoche pour rester visible au-dessus de
/// l'écran verrouillé : espace SkyLight de niveau supérieur, niveau du bouclier, affichage hors session.
@MainActor
final class LockScreenMediaWindow {
    private let panel = NotchPanel()
    private let viewModel: NotchViewModel
    private var isPinned = false

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        panel.contentView = LockScreenHostingView(rootView: LockScreenMediaRoot(viewModel: viewModel))
    }

    /// Affiche ou masque le lecteur selon l'état de l'encoche (appelé à chaque changement).
    func update(screen: NSScreen?, level: NSWindow.Level, space: LockScreenSpace?) {
        guard let screen, viewModel.lockScreenMediaModule != nil else {
            panel.orderOut(nil)
            return
        }
        let layout = NotchLayout.lockScreenMedia(screen: screen.frame)
        (panel.contentView as? LockScreenHostingView)?.rootView = LockScreenMediaRoot(viewModel: viewModel, layout: layout)
        panel.setFrame(layout.frame, display: false)
        panel.level = level
        panel.orderFrontRegardless()
        if !isPinned, let space {
            space.pin(panel)
            isPinned = true
        }
    }
}

/// Le premier clic sur la fenêtre (jamais au premier plan) agit tout de suite : sans cela, il ne
/// servait qu'à activer la fenêtre, et un clic sur deux était perdu.
final class LockScreenHostingView: NSHostingView<LockScreenMediaRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Contenu de la fenêtre : le grand lecteur du module, en haut, avec les tailles de l'écran.
struct LockScreenMediaRoot: View {
    let viewModel: NotchViewModel
    var layout = NotchLayout.lockScreenMedia(screen: CGRect(x: 0, y: 0, width: 1512, height: 982))

    var body: some View {
        Group {
            if let view = viewModel.lockScreenMediaModule?.lockScreenMedia() {
                view
            }
        }
        .environment(\.lockScreenMedia, layout)
        .tint(viewModel.appearance.accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(layout.margin)
    }
}
