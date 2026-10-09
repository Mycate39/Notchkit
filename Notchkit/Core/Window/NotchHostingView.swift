import AppKit
import SwiftUI
import os

/// Journal du glisser-déposer (visible avec `log show --predicate 'category == "drop"'`).
let dropLog = Logger(subsystem: "com.andeolchenaux.notchkit", category: "drop")

/// Vue d'hébergement SwiftUI qui détecte l'entrée et la sortie de la souris.
///
/// On utilise une `NSTrackingArea` : macOS nous prévient uniquement quand la souris
/// franchit le bord de la fenêtre, sans suivi permanent de la souris (économe en CPU).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    /// Position de la souris dans la fenêtre : écart horizontal au centre et distance au bord haut.
    /// Sert à distinguer la grande encoche des bulles, qui partagent la même fenêtre.
    var onPointerMove: ((_ dx: CGFloat, _ fromTop: CGFloat) -> Void)?
    /// Glisser-déposer de fichiers : position horizontale normalisée (0…1), `nil` = sortie/fin.
    var onFileDrag: ((CGFloat?) -> Void)?
    /// Fichiers déposés, avec la position horizontale normalisée du dépôt.
    var onFileDrop: (([URL], CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, .string])
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

    /// Texte glissé (sélection d'une page web, d'un document…), quand il n'y a pas de fichier.
    private func droppedText(from info: NSDraggingInfo) -> String? {
        guard info.draggingSource == nil else { return nil }
        let text = info.draggingPasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func hasDroppableContent(_ info: NSDraggingInfo) -> Bool {
        !fileURLs(from: info).isEmpty || droppedText(from: info) != nil
    }

    private func normalizedX(_ info: NSDraggingInfo) -> CGFloat {
        let point = convert(info.draggingLocation, from: nil)
        return bounds.width > 0 ? min(1, max(0, point.x / bounds.width)) : 0.5
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let count = fileURLs(from: sender).count
        dropLog.notice("entrée du glissement : \(count) fichier(s), source interne : \(sender.draggingSource != nil)")
        guard hasDroppableContent(sender) else { return [] }
        onFileDrag?(normalizedX(sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasDroppableContent(sender) else { return [] }
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
        hasDroppableContent(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var urls = fileURLs(from: sender)
        // Texte sans fichier : enregistré dans un petit fichier texte, qui se récupère comme les autres.
        if urls.isEmpty, let text = droppedText(from: sender), let file = ShelfTextClipping.save(text) {
            urls = [file]
        }
        dropLog.notice("dépôt : \(urls.count) élément(s)")
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls, normalizedX(sender))
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        // `.inVisibleRect` : la zone suit automatiquement la taille de la vue.
        // `.mouseMoved` : mouvements reçus seulement quand la souris est au-dessus de la fenêtre.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        reportPointer(event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportPointer(event)
    }

    private func reportPointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let fromTop = isFlipped ? point.y : bounds.height - point.y
        onPointerMove?(point.x - bounds.midX, fromTop)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }

    // Le premier clic agit directement, même si le panneau n'est pas actif.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
