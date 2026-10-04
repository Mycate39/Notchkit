import AppKit
import QuickLookThumbnailing

/// Fichier posé sur l'étagère. On garde un « signet » (bookmark) plutôt qu'un simple chemin :
/// le fichier est retrouvé même s'il est renommé ou déplacé sur le même disque.
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let bookmark: Data
    /// Nom au moment du dépôt (affiché si le fichier a disparu).
    let name: String
    let addedAt: Date

    init?(url: URL, date: Date = Date()) {
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        id = UUID()
        self.bookmark = bookmark
        name = url.lastPathComponent
        addedAt = date
    }

    /// Emplacement actuel du fichier, ou `nil` s'il n'existe plus.
    func resolvedURL() -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}

/// Aperçus des fichiers (Quick Look), mis en cache. À défaut d'aperçu : l'icône du Finder.
@MainActor
@Observable
final class ShelfThumbnails {
    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var requested = Set<URL>()

    func image(for url: URL) -> NSImage {
        if let image = images[url] { return image }
        load(url)
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func load(_ url: URL) {
        guard requested.insert(url).inserted else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.images[url] = image }
            }
        }
    }
}
