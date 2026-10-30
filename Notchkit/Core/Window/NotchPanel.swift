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
        // Fenêtre clé seulement pour un champ de texte (traducteur, notes) : un clic sur un bouton (roue
        // dentée) la rendait clé, et la fenêtre des réglages ouverte ensuite restait grisée.
        becomesKeyOnlyIfNeeded = true
        level = Self.normalLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Autorise l'affichage hors session : sans cela, macOS masque la fenêtre à l'écran verrouillé.
        canBecomeVisibleWithoutLogin = true
    }

    /// Niveau habituel : juste au-dessus de la barre des menus.
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    /// Niveau à l'écran verrouillé : au-dessus du « bouclier » qui masque les fenêtres pendant le verrouillage.
    static let lockedLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

    // Peut devenir « key » (utile plus tard pour les champs de texte), jamais fenêtre principale.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Par défaut, AppKit empêche une fenêtre de chevaucher la barre des menus : on désactive ce comportement.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
