import Foundation

/// Texte glissé sur l'encoche : enregistré dans un fichier `.txt` (Application Support), pour être
/// gardé sur l'étagère et récupéré par glisser-déposer comme n'importe quel fichier.
enum ShelfTextClipping {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit/Shelf", isDirectory: true)
    }

    /// Nom du fichier : début du texte (sans caractères interdits), sinon « Texte ».
    static func fileName(for text: String, maxLength: Int = 40) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = firstLine
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Un nom qui commence par un point serait un fichier caché du Finder.
            .drop(while: { $0 == "." || $0.isWhitespace })
        let base = cleaned.isEmpty ? String(localized: "Texte") : String(cleaned.prefix(maxLength))
        return base + ".txt"
    }

    /// Le fichier est un texte déposé, enregistré par Notchkit dans `folder` (fonction pure, testée).
    static func isClipping(_ url: URL, in folder: URL = folder) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == folder.standardizedFileURL.path
    }

    /// Efface les textes déposés parmi ces fichiers (ils ont quitté l'étagère) ; les autres fichiers
    /// ne sont jamais touchés.
    static func discard(_ urls: [URL]) {
        for url in urls where isClipping(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func save(_ text: String) -> URL? {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent(fileName(for: text))
        // Nom déjà pris : « Nom 2.txt », « Nom 3.txt »…
        var index = 2
        while manager.fileExists(atPath: url.path) {
            let name = fileName(for: text).dropLast(4)
            url = folder.appendingPathComponent("\(name) \(index).txt")
            index += 1
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
