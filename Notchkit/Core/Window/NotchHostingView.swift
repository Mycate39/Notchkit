import AppKit
import SwiftUI

/// Vue d'hébergement SwiftUI qui détecte l'entrée et la sortie de la souris.
///
/// On utilise une `NSTrackingArea` : macOS nous prévient uniquement quand la souris
/// franchit le bord de la fenêtre, sans suivi permanent de la souris (économe en CPU).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        // `.inVisibleRect` : la zone suit automatiquement la taille de la vue.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }

    // Le premier clic agit directement, même si le panneau n'est pas actif.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
