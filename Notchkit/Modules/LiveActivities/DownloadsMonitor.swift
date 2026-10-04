import Foundation

/// Suit les téléchargements en cours dans le dossier Téléchargements.
///
/// Les navigateurs écrivent d'abord un fichier temporaire (`.crdownload` pour Brave/Chrome,
/// `.download` pour Safari, `.part` pour Firefox), renommé à la fin. On surveille le dossier
/// (notifications du système de fichiers) et, tant qu'un téléchargement est en cours, on relève
/// sa taille une fois par seconde. Safari fournit en plus la taille totale (progression exacte).
///
/// macOS demande l'autorisation d'accéder au dossier Téléchargements au premier démarrage.
@MainActor
final class DownloadsMonitor {
    struct Download: Equatable, Sendable {
        let temporaryURL: URL
        let name: String
        var bytes: Int64
        var total: Int64?
    }

    var onUpdate: (@MainActor ([Download]) -> Void)?
    var onFinished: (@MainActor (URL) -> Void)?

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var pollTask: Task<Void, Never>?
    private var current: [URL: Download] = [:]

    init(directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.directory = directory
    }

    func start() {
        guard source == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        scan()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTask?.cancel()
        pollTask = nil
        current.removeAll()
    }

    private func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var found: [URL: Download] = [:]
        for url in files where DownloadFiles.isTemporary(url.lastPathComponent) {
            found[url] = Self.read(url)
        }

        // Fichiers temporaires disparus : le téléchargement est terminé si le fichier final existe.
        for (url, download) in current where found[url] == nil {
            let finalURL = url.deletingLastPathComponent().appendingPathComponent(DownloadFiles.finalName(for: url.lastPathComponent))
            if FileManager.default.fileExists(atPath: finalURL.path), !download.name.hasPrefix("Unconfirmed") {
                onFinished?(finalURL)
            }
        }

        if found != current {
            current = found
            onUpdate?(Array(found.values).sorted { $0.name < $1.name })
        }
        updatePolling()
    }

    /// Relevé de taille chaque seconde, seulement tant qu'un téléchargement est en cours.
    private func updatePolling() {
        if current.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        } else if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self?.scan()
                }
            }
        }
    }

    private static func read(_ url: URL) -> Download {
        let name = DownloadFiles.finalName(for: url.lastPathComponent)
        // Safari : un paquet `.download` contenant le fichier et un Info.plist de progression.
        if url.pathExtension == "download",
           let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) {
            let bytes = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
            let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            return Download(temporaryURL: url, name: name, bytes: bytes, total: total.flatMap { $0 > 0 ? $0 : nil })
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Download(temporaryURL: url, name: name, bytes: Int64(size), total: nil)
    }
}
