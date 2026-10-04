import AppKit

/// Zones proposées quand on fait glisser des fichiers sur l'encoche.
enum DropZone: String, Sendable {
    /// Garder les fichiers dans l'étagère.
    case shelf
    /// Les envoyer par AirDrop.
    case airDrop

    /// Zone survolée selon la position horizontale (0 = bord gauche, 1 = bord droit) :
    /// étagère à gauche, AirDrop à droite. Sans étagère, tout l'espace sert à AirDrop.
    static func zone(atNormalizedX x: CGFloat, shelfAvailable: Bool) -> DropZone {
        guard shelfAvailable else { return .airDrop }
        return x < 0.5 ? .shelf : .airDrop
    }
}

/// Envoi par AirDrop (API publique `NSSharingService`).
enum AirDrop {
    @MainActor
    static var isAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    /// Ouvre la fenêtre AirDrop de macOS pour choisir l'appareil destinataire.
    @MainActor
    @discardableResult
    static func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else { return false }
        // App sans icône dans le Dock : on la passe au premier plan pour que la fenêtre soit visible.
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }
}
