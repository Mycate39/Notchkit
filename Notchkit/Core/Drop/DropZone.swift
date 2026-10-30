import AppKit

/// Zones proposées quand on fait glisser des fichiers sur l'encoche.
enum DropZone: String, Sendable {
    /// Garder les fichiers dans l'étagère.
    case shelf
    /// Les convertir dans un autre format (widget Convertisseur).
    case convert
    /// Les envoyer par AirDrop.
    case airDrop

    /// Zone survolée selon la position horizontale (0 = bord gauche, 1 = bord droit) : les zones
    /// disponibles se partagent la largeur, de gauche à droite (étagère, conversion, AirDrop).
    static func zone(atNormalizedX x: CGFloat, zones: [DropZone]) -> DropZone {
        guard !zones.isEmpty else { return .airDrop }
        let index = Int(min(max(x, 0), 0.9999) * CGFloat(zones.count))
        return zones[index]
    }

    static func zone(atNormalizedX x: CGFloat, shelfAvailable: Bool) -> DropZone {
        zone(atNormalizedX: x, zones: shelfAvailable ? [.shelf, .airDrop] : [.airDrop])
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

extension NSItemProvider {
    /// Fichier glissé hors de l'encoche (étagère, convertisseur, captures) : on passe son lien, pour
    /// que le Finder le copie sous son vrai nom. Avec `NSItemProvider(contentsOf:)`, il recevait les
    /// données seules et créait « Image PNG.png ».
    static func file(at url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
