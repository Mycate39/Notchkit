import AppKit
import AVFoundation
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Format de sortie proposé par le convertisseur.
enum ConversionFormat: String, CaseIterable, Identifiable, Sendable {
    // Images
    case jpeg, png, heic, tiff
    // Audio
    case m4a, wav, aiff, flac
    // Vidéo
    case mp4, mov, gif
    // Documents
    case pdf, docx, rtf, odt, html, txt

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        default: rawValue
        }
    }

    /// Nom court affiché sur le bouton.
    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .docx: "Word"
        case .odt: "ODT"
        case .txt: String(localized: "Texte")
        case .gif: "GIF"
        default: rawValue.uppercased()
        }
    }
}

/// Famille d'un fichier, qui décide des formats de sortie possibles.
enum ConversionKind: Equatable, Sendable {
    case image, audio, video, document, pdf

    var symbol: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .document: "doc.text"
        case .pdf: "doc.richtext"
        }
    }

    /// Formats proposés pour cette famille (fonction pure, testée).
    var formats: [ConversionFormat] {
        switch self {
        case .image: [.jpeg, .png, .heic, .tiff, .pdf]
        case .audio: [.m4a, .wav, .aiff, .flac]
        case .video: [.mp4, .mov, .gif, .m4a]
        case .document: [.pdf, .docx, .rtf, .odt, .html, .txt]
        case .pdf: [.txt, .png, .jpeg]
        }
    }

    /// Famille d'un type de fichier, ou `nil` s'il n'est pas pris en charge.
    static func of(_ type: UTType) -> ConversionKind? {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        let documents: [UTType] = [.plainText, .rtf, .rtfd, .html,
                                   UTType("org.openxmlformats.wordprocessingml.document"),
                                   UTType("com.microsoft.word.doc"),
                                   UTType("org.oasis-open.opendocument.text"),
                                   UTType("net.daringfireball.markdown")].compactMap { $0 }
        if documents.contains(where: { type.conforms(to: $0) }) { return .document }
        return nil
    }

    static func of(_ url: URL) -> ConversionKind? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type.flatMap(of)
    }
}

enum ConversionError: LocalizedError {
    case unreadable
    case failed

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Fichier illisible ou format non pris en charge.")
        case .failed: String(localized: "La conversion a échoué.")
        }
    }
}

/// Conversions faites sur le Mac avec les outils du système : ImageIO, afconvert, AVFoundation,
/// CoreText et PDFKit. Le résultat est écrit à côté de l'original (ou dans Téléchargements).
enum FileConverter {
    /// Formats proposés pour un fichier, sans son propre format.
    static func formats(for url: URL) -> [ConversionFormat] {
        guard let kind = ConversionKind.of(url) else { return [] }
        let ext = normalizedExtension(url.pathExtension)
        return kind.formats.filter { $0.fileExtension != ext }
    }

    /// Extension ramenée à celle du format (« jpeg » → « jpg », « tif » → « tiff »…).
    static func normalizedExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg": "jpg"
        case "tif": "tiff"
        case "htm": "html"
        case "aif": "aiff"
        case let other: other
        }
    }

    /// Formats communs à plusieurs fichiers : ceux de leurs familles, sauf un format que tous ont déjà
    /// (un fichier déjà au format choisi est simplement ignoré).
    static func commonFormats(for urls: [URL]) -> [ConversionFormat] {
        let kinds = urls.map(ConversionKind.of)
        guard let first = kinds.first, let firstKind = first else { return [] }
        var common = firstKind.formats
        for kind in kinds.dropFirst() {
            guard let kind else { return [] }
            common = common.filter(kind.formats.contains)
        }
        let extensions = Set(urls.map { normalizedExtension($0.pathExtension) })
        return common.filter { extensions != [$0.fileExtension] || firstKind == .pdf }
    }

    /// Le fichier est déjà au format demandé (rien à faire).
    static func isAlready(_ url: URL, in format: ConversionFormat) -> Bool {
        ConversionKind.of(url) != .pdf && normalizedExtension(url.pathExtension) == format.fileExtension
    }

    static func destination(for url: URL, format: ConversionFormat) -> URL {
        FileActions.uniqueURL(named: url.deletingPathExtension().lastPathComponent, extension: format.fileExtension,
                              in: FileActions.outputFolder(for: url))
    }

    /// Convertit un fichier ; renvoie le fichier (ou le dossier, pour les pages d'un PDF) créé.
    /// `progress` reçoit l'avancement de ce fichier (0 à 1) pour les conversions longues (vidéo, GIF, PDF).
    @MainActor
    static func convert(_ url: URL, to format: ConversionFormat,
                        progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> URL {
        guard let kind = ConversionKind.of(url) else { throw ConversionError.unreadable }
        switch (kind, format) {
        case (.image, .pdf): return try await imageToPDF(url)
        case (.image, _): return try await convertImage(url, to: format)
        case (.audio, _): return try await convertAudio(url, to: format)
        case (.video, .gif): return try await videoToGIF(url, progress: progress)
        case (.video, _): return try await exportVideo(url, to: format, progress: progress)
        case (.document, _): return try await convertDocument(url, to: format)
        case (.pdf, .txt): return try await pdfToText(url)
        case (.pdf, _): return try await pdfToImages(url, format: format, progress: progress)
        }
    }

    // MARK: Images

    private static func imageType(_ format: ConversionFormat) -> UTType {
        switch format {
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        default: .jpeg
        }
    }

    private static func convertImage(_ url: URL, to format: ConversionFormat) async throws -> URL {
        let destination = destination(for: url, format: format)
        let type = imageType(format)
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let (image, metadata) = orientedImage(at: url) else { return false }
            return write(image, to: destination, type: type, metadata: metadata)
        }.value
        guard ok else {
            try? FileManager.default.removeItem(at: destination)
            throw ConversionError.failed
        }
        return destination
    }

    /// Métadonnées gardées d'une photo : date, appareil, lieu (EXIF, TIFF, GPS, IPTC).
    nonisolated private static var keptMetadata: [CFString] {
        [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
         kCGImagePropertyIPTCDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
    }

    /// Image prête à écrire, déjà tournée selon son orientation (une photo d'iPhone est enregistrée
    /// couchée, avec une étiquette « à tourner » que tous les logiciels ne lisent pas), et ses
    /// métadonnées, étiquette remise à « droite ». Les images qu'ImageIO ne lit pas (SVG) passent par
    /// AppKit.
    nonisolated static func orientedImage(at url: URL) -> (CGImage, [CFString: Any])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return rasterized(url).map { ($0, [:]) } }
        var metadata = properties.filter { keptMetadata.contains($0.key) }
        metadata[kCGImagePropertyOrientation] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let image: CGImage?
        if orientation == 1 || width == 0 || height == 0 {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            ] as CFDictionary)
        }
        return image.map { ($0, metadata) }
    }

    /// Côté le plus long d'une image vectorielle (SVG) rendue en pixels.
    nonisolated static let vectorRenderSide: CGFloat = 2048

    /// Image vectorielle (SVG) rendue en pixels par AppKit, à `vectorRenderSide` pixels de côté.
    nonisolated private static func rasterized(_ url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = vectorRenderSide / max(image.size.width, image.size.height)
        let width = Int((image.size.width * scale).rounded()), height = Int((image.size.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    nonisolated private static func write(_ image: CGImage, to url: URL, type: UTType, metadata: [CFString: Any] = [:]) -> Bool {
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var options = metadata
        options[kCGImageDestinationLossyCompressionQuality] = 0.9
        CGImageDestinationAddImage(output, image, options as CFDictionary)
        return CGImageDestinationFinalize(output)
    }

    /// Taille de la page d'une image mise en PDF : ses pixels à sa résolution (72 ppp par défaut),
    /// comme dans Aperçu (fonction pure, testée).
    nonisolated static func pdfPageSize(pixels: CGSize, dpi: CGSize) -> CGSize {
        CGSize(width: pixels.width * 72 / (dpi.width > 0 ? dpi.width : 72),
               height: pixels.height * 72 / (dpi.height > 0 ? dpi.height : 72))
    }

    private static func imageToPDF(_ url: URL) async throws -> URL {
        let destination = destination(for: url, format: .pdf)
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let (image, metadata) = orientedImage(at: url) else { return false }
            let dpi = CGSize(width: metadata[kCGImagePropertyDPIWidth] as? CGFloat ?? 72,
                             height: metadata[kCGImagePropertyDPIHeight] as? CGFloat ?? 72)
            var box = CGRect(origin: .zero, size: pdfPageSize(pixels: CGSize(width: image.width, height: image.height), dpi: dpi))
            guard let context = CGContext(destination as CFURL, mediaBox: &box, nil) else { return false }
            context.beginPDFPage(nil)
            context.interpolationQuality = .high
            context.draw(image, in: box)
            context.endPDFPage()
            context.closePDF()
            return true
        }.value
        guard ok else {
            try? FileManager.default.removeItem(at: destination)
            throw ConversionError.failed
        }
        return destination
    }

    // MARK: Audio (outil afconvert du Mac)

    /// Arguments d'afconvert pour un format (fonction pure, testée).
    static func afconvertArguments(for format: ConversionFormat) -> [String] {
        switch format {
        case .wav: ["-f", "WAVE", "-d", "LEI16"]
        case .aiff: ["-f", "AIFF", "-d", "BEI16"]
        case .flac: ["-f", "flac", "-d", "flac"]
        default: ["-f", "m4af", "-d", "aac", "-b", "256000"]
        }
    }

    private static func convertAudio(_ url: URL, to format: ConversionFormat) async throws -> URL {
        let destination = destination(for: url, format: format)
        let arguments = afconvertArguments(for: format) + [url.path, destination.path]
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = arguments
            do { try process.run() } catch { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
        guard ok else {
            try? FileManager.default.removeItem(at: destination)
            throw ConversionError.failed
        }
        return destination
    }

    // MARK: Vidéo (AVFoundation)

    private static func exportVideo(_ url: URL, to format: ConversionFormat,
                                    progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let destination = destination(for: url, format: format)
        let (preset, type): (String, AVFileType) = switch format {
        case .mov: (AVAssetExportPresetHEVCHighestQuality, .mov)
        case .m4a: (AVAssetExportPresetAppleM4A, .m4a)
        default: (AVAssetExportPresetHighestQuality, .mp4)
        }
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else {
            throw ConversionError.unreadable
        }
        // Avancement lu toutes les 0,2 s pendant l'export (une longue vidéo prend plusieurs minutes).
        nonisolated(unsafe) let watched = session
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                progress(Double(watched.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: destination, as: type)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// GIF animé : 15 premières secondes au plus, 10 images par seconde, 480 points de large.
    static let gifMaxDuration: Double = 15
    static let gifFramesPerSecond: Double = 10
    static let gifMaxWidth: CGFloat = 480

    private static func videoToGIF(_ url: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let destination = destination(for: url, format: .gif)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ConversionError.unreadable }
        let length = min(duration, gifMaxDuration)
        let count = max(1, Int(length * gifFramesPerSecond))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: gifMaxWidth, height: gifMaxWidth * 4)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)

        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ConversionError.failed
        }
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / gifFramesPerSecond]] as CFDictionary
        do {
            for index in 0..<count {
                try Task.checkCancellation()
                let time = CMTime(seconds: Double(index) / gifFramesPerSecond, preferredTimescale: 600)
                let image = try await generator.image(at: time).image
                CGImageDestinationAddImage(output, image, frame)
                await progress(Double(index + 1) / Double(count))
            }
            guard CGImageDestinationFinalize(output) else { throw ConversionError.failed }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    // MARK: Documents (AppKit et CoreText)

    private static func documentType(_ format: ConversionFormat) -> NSAttributedString.DocumentType {
        switch format {
        case .docx: .officeOpenXML
        case .rtf: .rtf
        case .odt: .openDocument
        case .html: .html
        default: .plain
        }
    }

    @MainActor
    private static func convertDocument(_ url: URL, to format: ConversionFormat) async throws -> URL {
        // Lecture sur le fil principal : l'import HTML d'AppKit l'exige.
        let text: NSAttributedString
        if ["md", "markdown"].contains(url.pathExtension.lowercased()),
           let source = try? String(contentsOf: url, encoding: .utf8),
           let markdown = MarkdownText.attributed(source) {
            text = markdown
        } else {
            guard let read = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
                throw ConversionError.unreadable
            }
            text = read
        }
        let destination = destination(for: url, format: format)
        // Mise en pages et écriture hors du fil principal : un long document ne fige pas l'encoche.
        // Le texte lu n'est plus touché ici, il passe seul à la tâche.
        nonisolated(unsafe) let content = text
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            if format == .pdf { return renderPDF(content, to: destination) }
            let type = documentType(format)
            var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
            if type == .plain || type == .html { attributes[.characterEncoding] = String.Encoding.utf8.rawValue }
            guard let data = try? content.data(from: NSRange(location: 0, length: content.length), documentAttributes: attributes)
            else { return false }
            return (try? data.write(to: destination)) != nil
        }.value
        guard ok else {
            try? FileManager.default.removeItem(at: destination)
            throw ConversionError.failed
        }
        return destination
    }

    /// Page A4 et marges du PDF (points).
    static let pageSize = CGSize(width: 595, height: 842)
    static let pageMargin: CGFloat = 56

    /// Mise en pages du texte en PDF A4 (CoreText) ; le texte sans police reçoit celle du système.
    static func renderPDF(_ text: NSAttributedString, to url: URL) -> Bool {
        let content = NSMutableAttributedString(attributedString: text)
        content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            if value == nil { content.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: range) }
        }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        let frameRect = box.insetBy(dx: pageMargin, dy: pageMargin)
        var start = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), CGPath(rect: frameRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            // Sécurité : une page qui n'avance pas (ligne plus haute que la page) arrête la boucle.
            guard visible.length > 0 else { break }
            start += visible.length
        } while start < content.length
        context.closePDF()
        return true
    }

    // MARK: PDF (PDFKit)

    private static func pdfToText(_ url: URL) async throws -> URL {
        let destination = destination(for: url, format: .txt)
        let result = await Task.detached(priority: .userInitiated) { () -> ConversionError? in
            guard let document = PDFDocument(url: url) else { return .unreadable }
            return (try? (document.string ?? "").write(to: destination, atomically: true, encoding: .utf8)) != nil ? nil : .failed
        }.value
        if let result { throw result }
        return destination
    }

    /// Dossier libre : « Nom », sinon « Nom 2 », « Nom 3 »…
    static func uniqueFolder(named base: String, in parent: URL,
                             exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var index = 2
        while exists(candidate) {
            candidate = parent.appendingPathComponent("\(base) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    /// Pages du PDF en images (2 × la taille de la page) : un fichier pour une page, un dossier sinon.
    /// Le rendu se fait hors du fil principal : un long PDF ne fige pas l'encoche.
    private static func pdfToImages(_ url: URL, format: ConversionFormat,
                                    progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let type = imageType(format)
        let base = url.deletingPathExtension().lastPathComponent
        let output = FileActions.outputFolder(for: url)
        let rendered = await Task.detached(priority: .userInitiated) { () -> Result<URL, ConversionError> in
            guard let document = PDFDocument(url: url), document.pageCount > 0 else { return .failure(.unreadable) }
            let count = document.pageCount
            let folder = count == 1 ? output : uniqueFolder(named: base, in: output)
            if count > 1 {
                do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                    return .failure(.failed)
                }
            }
            var single: URL?
            for index in 0..<count {
                if Task.isCancelled { break }
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let name = count == 1 ? base : String(localized: "Page \(index + 1)")
                let destination = FileActions.uniqueURL(named: name, extension: format.fileExtension, in: folder)
                guard write(cgImage, to: destination, type: type) else {
                    if count > 1 { try? FileManager.default.removeItem(at: folder) }
                    return .failure(.failed)
                }
                single = destination
                Task { @MainActor in progress(Double(index + 1) / Double(count)) }
            }
            if count == 1 { return single.map { .success($0) } ?? .failure(.failed) }
            return .success(folder)
        }.value
        return try rendered.get()
    }
}
