import AppKit
import SwiftUI

/// Vue d'hébergement SwiftUI qui détecte l'entrée et la sortie de la souris.
///
/// On utilise une `NSTrackingArea` : macOS nous prévient uniquement quand la souris
/// franchit le bord de la fenêtre, sans suivi permanent de la souris (économe en CPU).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    /// Glisser-déposer de fichiers : position horizontale normalisée (0…1), `nil` = sortie/fin.
    var onFileDrag: ((CGFloat?) -> Void)?
    /// Fichiers déposés, avec la position horizontale normalisée du dépôt.
    var onFileDrop: (([URL], CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    // MARK: Glisser-déposer de fichiers

    /// Fichiers glissés depuis une autre app. Les glissements partis de Notchkit (ex. un fichier
    /// sorti de l'étagère) sont ignorés : l'encoche ne doit pas passer en mode dépôt sous le curseur.
    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        guard info.draggingSource == nil else { return [] }
        return info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    private func normalizedX(_ info: NSDraggingInfo) -> CGFloat {
        let point = convert(info.draggingLocation, from: nil)
        return bounds.width > 0 ? min(1, max(0, point.x / bounds.width)) : 0.5
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        onFileDrag?(normalizedX(sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        onFileDrag?(normalizedX(sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onFileDrag?(nil)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onFileDrag?(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls, normalizedX(sender))
        return true
    }

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
