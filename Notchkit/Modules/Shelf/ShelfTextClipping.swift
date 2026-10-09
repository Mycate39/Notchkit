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
        let base = cleaned.isEmpty ? String(localized: "Texte") : String(cleaned.prefix(maxLength))
        return base + ".txt"
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
