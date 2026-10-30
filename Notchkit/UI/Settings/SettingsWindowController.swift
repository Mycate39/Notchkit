import AppKit
import SwiftUI

/// Fenêtre de réglages, gérée manuellement : plus fiable que la scène `Settings` de SwiftUI
/// pour une app sans icône dans le Dock (elle passe correctement au premier plan).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: @MainActor () -> AnyView

    init(makeContent: @escaping @MainActor () -> AnyView) {
        self.makeContent = makeContent
    }

    /// `title` : titre de la page ouverte, posé à la création de la fenêtre (SwiftUI ne le donne pas
    /// à la fenêtre au premier affichage, elle restait « Sans titre » ; il le met à jour ensuite).
    func show(title: String) {
        if window == nil {
            let controller = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: controller)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 860, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            // Taille et position retrouvées d'une ouverture à l'autre.
            window.setFrameAutosaveName("NotchkitSettings")
            self.window = window
        }
        if let window { WindowActivation.bringToFront(window) }
    }
}
