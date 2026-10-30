import Foundation

/// Actions sur les fichiers de l'étagère : ZIP et copie vers iCloud Drive. Tout est fait sur le Mac,
/// avec les outils du système (gratuit). Les conversions passent par `FileConverter`.
enum FileActions {
    /// Dossier de sortie : celui de l'original s'il est modifiable, sinon Téléchargements.
    static func outputFolder(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: folder.path) { return folder }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Nom libre dans `folder` : « Nom.ext », sinon « Nom 2.ext », « Nom 3.ext »…
    static func uniqueURL(named base: String, extension ext: String, in folder: URL,
                          exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    /// Nom d'un fichier sans son extension ; un dossier garde son nom entier (« Projet.v2 »).
    static func baseName(of url: URL) -> String {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        return isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    /// Noms des fichiers dans l'archive : deux fichiers de même nom (venus de dossiers différents)
    /// deviennent « Nom.ext » et « Nom 2.ext » (fonction pure, testée).
    static func archiveNames(for urls: [URL]) -> [String] {
        var taken = Set<String>()
        return urls.map { url in
            let ext = url.pathExtension
            let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            var name = url.lastPathComponent
            var index = 2
            // Le système de fichiers du Mac ne distingue pas les majuscules.
            while taken.contains(name.lowercased()) {
                name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
                index += 1
            }
            taken.insert(name.lowercased())
            return name
        }
    }

    /// Archive ZIP (outil `ditto` du Mac, comme « Compresser » dans le Finder).
    static func zip(_ urls: [URL]) async -> URL? {
        guard let first = urls.first else { return nil }
        let base = urls.count == 1 ? baseName(of: first) : String(localized: "Archive")
        let destination = uniqueURL(named: base, extension: "zip", in: outputFolder(for: first))
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let manager = FileManager.default
            var source = first
            var staging: URL?
            if urls.count > 1 {
                // Plusieurs fichiers : rassemblés dans un dossier temporaire (copies instantanées sur APFS),
                // puis archivés ensemble. Le dossier est effacé ensuite.
                let parent = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let folder = parent.appendingPathComponent(base)
                staging = parent
                do {
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    for (url, name) in Swift.zip(urls, archiveNames(for: urls)) {
                        try manager.copyItem(at: url, to: folder.appendingPathComponent(name))
                    }
                } catch {
                    try? manager.removeItem(at: parent)
                    return nil
                }
                source = folder
            }
            defer { if let staging { try? manager.removeItem(at: staging) } }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
            do { try process.run() } catch { return nil }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try? manager.removeItem(at: destination)
                return nil
            }
            return destination
        }.value
    }

    /// Dossier « Notchkit » d'iCloud Drive (`nil` si iCloud Drive n'est pas activé).
    static var iCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Notchkit", isDirectory: true)
    }

    /// Copie vers iCloud Drive (macOS se charge ensuite de l'envoi).
    static func copyToICloud(_ urls: [URL]) async -> [URL] {
        guard let folder = iCloudFolder else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [URL] in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return urls.compactMap { url in
                // Un dossier garde son nom entier (pas d'extension à remettre).
                let base = baseName(of: url)
                let ext = base == url.lastPathComponent ? "" : url.pathExtension
                let destination = uniqueURL(named: base, extension: ext, in: folder)
                return (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination : nil
            }
        }.value
    }
}
