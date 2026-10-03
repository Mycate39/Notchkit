import AppKit

/// Panneau sans bordure qui accueille l'encoche.
///
/// - non activant : cliquer dedans ne fait pas passer Notchkit au premier plan
///   et ne retire pas le focus à l'app en cours ;
/// - placé au-dessus de la barre des menus, sur tous les Spaces et par-dessus le plein écran ;
/// - transparent : seule la forme noire dessinée par SwiftUI est visible.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    // Peut devenir « key » (utile plus tard pour les champs de texte), jamais fenêtre principale.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Par défaut, AppKit empêche une fenêtre de chevaucher la barre des menus : on désactive ce comportement.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
