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
    case m4a, wav, aiff
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
        case .audio: [.m4a, .wav, .aiff]
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
    @MainActor
    static func convert(_ url: URL, to format: ConversionFormat) async throws -> URL {
        guard let kind = ConversionKind.of(url) else { throw ConversionError.unreadable }
        switch (kind, format) {
        case (.image, .pdf): return try await imageToPDF(url)
        case (.image, _): return try await convertImage(url, to: format)
        case (.audio, _): return try await convertAudio(url, to: format)
        case (.video, .gif): return try await videoToGIF(url)
        case (.video, _): return try await exportVideo(url, to: format)
        case (.document, _): return try await convertDocument(url, to: format)
        case (.pdf, .txt): return try pdfToText(url)
        case (.pdf, _): return try await pdfToImages(url, format: format)
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
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
            return write(image, to: destination, type: type)
        }.value
        guard ok else { throw ConversionError.failed }
        return destination
    }

    nonisolated private static func write(_ image: CGImage, to url: URL, type: UTType) -> Bool {
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(output)
    }

    private static func imageToPDF(_ url: URL) async throws -> URL {
        let destination = destination(for: url, format: .pdf)
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let context = CGContext(destination as CFURL, mediaBox: &box, nil) else { return false }
            context.beginPDFPage(nil)
            context.draw(image, in: box)
            context.endPDFPage()
            context.closePDF()
            return true
        }.value
        guard ok else { throw ConversionError.failed }
        return destination
    }

    // MARK: Audio (outil afconvert du Mac)

    /// Arguments d'afconvert pour un format (fonction pure, testée).
    static func afconvertArguments(for format: ConversionFormat) -> [String] {
        switch format {
        case .wav: ["-f", "WAVE", "-d", "LEI16"]
        case .aiff: ["-f", "AIFF", "-d", "BEI16"]
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

    private static func exportVideo(_ url: URL, to format: ConversionFormat) async throws -> URL {
        let destination = destination(for: url, format: format)
        let (preset, type): (String, AVFileType) = switch format {
        case .mov: (AVAssetExportPresetHEVCHighestQuality, .mov)
        case .m4a: (AVAssetExportPresetAppleM4A, .m4a)
        default: (AVAssetExportPresetHighestQuality, .mp4)
        }
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else {
            throw ConversionError.unreadable
        }
        try await session.export(to: destination, as: type)
        return destination
    }

    /// GIF animé : 15 premières secondes au plus, 10 images par seconde, 480 points de large.
    static let gifMaxDuration: Double = 15
    static let gifFramesPerSecond: Double = 10
    static let gifMaxWidth: CGFloat = 480

    private static func videoToGIF(_ url: URL) async throws -> URL {
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
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / gifFramesPerSecond, preferredTimescale: 600)
            let image = try await generator.image(at: time).image
            CGImageDestinationAddImage(output, image, frame)
        }
        guard CGImageDestinationFinalize(output) else { throw ConversionError.failed }
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
           let markdown = try? AttributedString(contentsOf: url, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            text = NSAttributedString(markdown)
        } else {
            guard let read = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
                throw ConversionError.unreadable
            }
            text = read
        }
        let destination = destination(for: url, format: format)
        if format == .pdf {
            guard renderPDF(text, to: destination) else { throw ConversionError.failed }
            return destination
        }
        let type = documentType(format)
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
        if type == .plain || type == .html { attributes[.characterEncoding] = String.Encoding.utf8.rawValue }
        guard let data = try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes),
              (try? data.write(to: destination)) != nil else { throw ConversionError.failed }
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

    private static func pdfToText(_ url: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw ConversionError.unreadable }
        let destination = destination(for: url, format: .txt)
        guard (try? (document.string ?? "").write(to: destination, atomically: true, encoding: .utf8)) != nil else {
            throw ConversionError.failed
        }
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
    @MainActor
    private static func pdfToImages(_ url: URL, format: ConversionFormat) async throws -> URL {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw ConversionError.unreadable }
        let type = imageType(format)
        let base = url.deletingPathExtension().lastPathComponent
        let folder: URL
        if document.pageCount == 1 {
            folder = FileActions.outputFolder(for: url)
        } else {
            folder = uniqueFolder(named: base, in: FileActions.outputFolder(for: url))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        var single: URL?
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let name = document.pageCount == 1 ? base : String(localized: "Page \(index + 1)")
            let destination = FileActions.uniqueURL(named: name, extension: format.fileExtension, in: folder)
            guard write(cgImage, to: destination, type: type) else { throw ConversionError.failed }
            single = destination
        }
        return document.pageCount == 1 ? (single ?? folder) : folder
    }
}
