import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Actions sur les fichiers de l'étagère : ZIP, conversion d'images et de vidéos, copie vers
/// iCloud Drive. Tout est fait sur le Mac, avec les outils du système (gratuit).
enum FileActions {
    enum ImageFormat: String, CaseIterable, Sendable {
        case jpeg, png, heic
        var type: UTType { switch self { case .jpeg: .jpeg; case .png: .png; case .heic: .heic } }
        var fileExtension: String { switch self { case .jpeg: "jpg"; case .png: "png"; case .heic: "heic" } }
    }

    static func isImage(_ url: URL) -> Bool { type(of: url)?.conforms(to: .image) ?? false }
    static func isVideo(_ url: URL) -> Bool { type(of: url)?.conforms(to: .movie) ?? false }

    private static func type(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
    }

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

    /// Archive ZIP (outil `ditto` du Mac, comme « Compresser » dans le Finder).
    static func zip(_ urls: [URL]) async -> URL? {
        guard let first = urls.first else { return nil }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : String(localized: "Archive")
        let destination = uniqueURL(named: base, extension: "zip", in: outputFolder(for: first))
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            if urls.count == 1 {
                process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, destination.path]
            } else {
                // Plusieurs fichiers : copiés dans un dossier temporaire, puis archivés ensemble.
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(base)
                try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                for url in urls { try? FileManager.default.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent)) }
                process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, destination.path]
            }
            do { try process.run() } catch { return nil }
            process.waitUntilExit()
            return process.terminationStatus == 0 ? destination : nil
        }.value
    }

    /// Conversion d'image (ImageIO).
    static func convertImage(_ url: URL, to format: ImageFormat) async -> URL? {
        let destination = uniqueURL(named: url.deletingPathExtension().lastPathComponent, extension: format.fileExtension,
                                    in: outputFolder(for: url))
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let output = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil)
            else { return nil }
            let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
            CGImageDestinationAddImage(output, image, options)
            return CGImageDestinationFinalize(output) ? destination : nil
        }.value
    }

    /// Conversion de vidéo en MP4 (H.264, AVFoundation).
    static func convertVideoToMP4(_ url: URL) async -> URL? {
        let destination = uniqueURL(named: url.deletingPathExtension().lastPathComponent, extension: "mp4",
                                    in: outputFolder(for: url))
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        do {
            try await session.export(to: destination, as: .mp4)
            return destination
        } catch {
            return nil
        }
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
                let destination = uniqueURL(named: url.deletingPathExtension().lastPathComponent,
                                            extension: url.pathExtension, in: folder)
                return (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination : nil
            }
        }.value
    }
}
