import AppKit
import AVFoundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Notchkit

struct ConverterFormatTests {
    @Test func formatsSelonLaFamille() {
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/photo.jpeg")) == [.png, .heic, .tiff, .pdf])
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/son.wav")) == [.m4a, .aiff, .flac])
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/film.mov")) == [.mp4, .gif, .m4a])
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/lettre.docx")) == [.pdf, .rtf, .odt, .html, .txt])
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/notice.pdf")) == [.txt, .png, .jpeg])
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/archive.zip")).isEmpty)
    }

    @Test func fichiersIncompatiblesEcartes() {
        let urls = ["a.png", "b.zip", "c.jpg", "d.mp3"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        // Les images gardent des formats communs ; le son n'en a aucun avec elles.
        #expect(ConverterModule.supported(urls).map(\.lastPathComponent) == ["a.png", "c.jpg"])
    }

    @Test func formatsCommunsAPlusieursFichiers() {
        let urls = ["a.heic", "b.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        // JPEG reste proposé : seul b.jpg est déjà dans ce format, il sera ignoré.
        #expect(FileConverter.commonFormats(for: urls) == [.jpeg, .png, .heic, .tiff, .pdf])
        #expect(FileConverter.isAlready(urls[1], in: .jpeg))
        #expect(!FileConverter.isAlready(urls[0], in: .jpeg))
    }

    @Test @MainActor func widgetTemporaireVisibleAvecDesFichiers() {
        #expect(ConverterModule.descriptor.contextual)
        let module = ConverterModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
        #expect(!module.hasContextualContent)
        module.add([URL(fileURLWithPath: "/tmp/photo.heic")])
        #expect(module.hasContextualContent)
        module.clear()
        #expect(!module.hasContextualContent)
    }

    @Test func zonesDeDepotSePartagentLaLargeur() {
        let zones: [DropZone] = [.shelf, .convert, .airDrop]
        #expect(DropZone.zone(atNormalizedX: 0.1, zones: zones) == .shelf)
        #expect(DropZone.zone(atNormalizedX: 0.5, zones: zones) == .convert)
        #expect(DropZone.zone(atNormalizedX: 1, zones: zones) == .airDrop)
        #expect(DropZone.zone(atNormalizedX: 0.3, zones: [.convert, .airDrop]) == .convert)
    }

    @Test func fichiersDeposesAjoutesAuxFichiersEnAttente() {
        let url = { (name: String) in URL(fileURLWithPath: "/tmp/\(name)") }
        // Même famille : ajoutés, sans doublon.
        #expect(ConverterModule.merged(pending: [url("a.png")], dropped: [url("b.jpg"), url("a.png")])
            == [url("a.png"), url("b.jpg")])
        // Autre famille : ils remplacent les fichiers en attente, même avec un format commun (PDF).
        #expect(ConverterModule.merged(pending: [url("a.png")], dropped: [url("son.wav")]) == [url("son.wav")])
        #expect(ConverterModule.merged(pending: [url("lettre.docx")], dropped: [url("a.png")]) == [url("a.png")])
        // Rien de convertible : rien ne change (le module garde ses fichiers et affiche l'erreur).
        #expect(ConverterModule.merged(pending: [url("a.png")], dropped: [url("x.zip")]).isEmpty)
        #expect(ConverterModule.merged(pending: [url("a.png")], dropped: [url("a.png")]) == [url("a.png")])
    }

    @Test func avancementGlobal() {
        #expect(ConverterModule.progress(completed: 0, current: 0, total: 0) == 0)
        #expect(ConverterModule.progress(completed: 1, current: 0.5, total: 2) == 0.75)
        #expect(ConverterModule.progress(completed: 2, current: 3, total: 2) == 1)
    }

    @Test func pageDUneImageMiseEnPDF() {
        #expect(FileConverter.pdfPageSize(pixels: CGSize(width: 600, height: 300), dpi: CGSize(width: 144, height: 144))
            == CGSize(width: 300, height: 150))
        #expect(FileConverter.pdfPageSize(pixels: CGSize(width: 600, height: 300), dpi: .zero) == CGSize(width: 600, height: 300))
    }

    @Test @MainActor func markdownMisEnForme() throws {
        let source = """
        # Titre

        Du **gras**, de l'*italique* et du `code`.

        - un
        - deux

        1. premier

        | A | B |
        |---|---|
        | x | y |
        """
        let text = try #require(MarkdownText.attributed(source))
        let lines = text.string.components(separatedBy: "\n")
        #expect(lines == ["Titre", "Du gras, de l'italique et du code.", "• un", "• deux", "1. premier", "A\tB", "x\ty"])
        func font(at substring: String) -> NSFont? {
            let range = (text.string as NSString).range(of: substring)
            return text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        }
        #expect(font(at: "Titre")?.pointSize == MarkdownText.headerSize(level: 1))
        #expect(font(at: "Titre")?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font(at: "gras")?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font(at: "italique")?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(font(at: "code.")?.isFixedPitch == true)
        #expect(font(at: "A\t")?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func argumentsAfconvert() {
        #expect(FileConverter.afconvertArguments(for: .wav).contains("WAVE"))
        #expect(FileConverter.afconvertArguments(for: .m4a).contains("aac"))
        #expect(FileConverter.afconvertArguments(for: .flac).contains("flac"))
    }
}

/// Vraies conversions dans un dossier temporaire.
@MainActor
struct ConverterEngineTests {
    let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notchkit-convert-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func makePNG() throws -> URL {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.6, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let url = folder.appendingPathComponent("image.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func size(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// Photo « couchée » avec l'étiquette « à tourner » (orientation 6, comme une photo d'iPhone) :
    /// la sortie est déjà tournée, étiquette remise à droite, et garde ses métadonnées.
    @Test func photoTourneeGardeSonSens() async throws {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let jpeg = folder.appendingPathComponent("photo.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Objectif d'essai"],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        for format in [ConversionFormat.png, .heic] {
            let output = try await FileConverter.convert(jpeg, to: format)
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect(properties[kCGImagePropertyPixelWidth] as? Int == 20)
            #expect(properties[kCGImagePropertyPixelHeight] as? Int == 40)
            #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect(exif?[kCGImagePropertyExifLensModel] as? String == "Objectif d'essai")
        }
        let pdf = try await FileConverter.convert(jpeg, to: .pdf)
        let page = try #require(PDFDocument(url: pdf)?.page(at: 0))
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 20, height: 40))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func svgConverti() async throws {
        let svg = folder.appendingPathComponent("logo.svg")
        try ##"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10" fill="#f80"/></svg>"##
            .write(to: svg, atomically: true, encoding: .utf8)
        #expect(FileConverter.formats(for: svg).contains(.png))
        let png = try await FileConverter.convert(svg, to: .png)
        let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Int(FileConverter.vectorRenderSide))
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == Int(FileConverter.vectorRenderSide / 2))
        try? FileManager.default.removeItem(at: folder)
    }

    /// Conversion ratée : aucun fichier à moitié écrit ne reste.
    @Test func echecSansFichierAMoitieEcrit() async throws {
        let broken = folder.appendingPathComponent("abime.mp4")
        try Data(repeating: 7, count: 4096).write(to: broken)
        await #expect(throws: (any Error).self) { try await FileConverter.convert(broken, to: .mov) }
        await #expect(throws: (any Error).self) { try await FileConverter.convert(broken, to: .gif) }
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left == ["abime.mp4"])
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func imagesConverties() async throws {
        let png = try makePNG()
        for format in [ConversionFormat.jpeg, .heic, .tiff, .pdf] {
            let output = try await FileConverter.convert(png, to: format)
            #expect(output.pathExtension == format.fileExtension)
            #expect(size(output) > 0)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func sonConverti() async throws {
        let wav = folder.appendingPathComponent("son.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let samples = MascotSounds.render(MascotSounds.variants(of: .happy)[0], sampleRate: 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            try file.write(from: buffer)
        }
        for target in [ConversionFormat.m4a, .aiff, .flac] {
            let output = try await FileConverter.convert(wav, to: target)
            #expect(size(output) > 0)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func documentConvertiEnPDFEtEnWord() async throws {
        let rtf = folder.appendingPathComponent("lettre.rtf")
        let text = NSAttributedString(string: String(repeating: "Bonjour depuis l'encoche. ", count: 400))
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try data.write(to: rtf)

        let pdf = try await FileConverter.convert(rtf, to: .pdf)
        let document = try #require(PDFDocument(url: pdf))
        #expect(document.pageCount >= 2)
        #expect(document.string?.contains("Bonjour") == true)

        let docx = try await FileConverter.convert(rtf, to: .docx)
        #expect(size(docx) > 0)

        // PDF → texte, et PDF de plusieurs pages → un dossier d'images.
        let txt = try await FileConverter.convert(pdf, to: .txt)
        #expect((try String(contentsOf: txt, encoding: .utf8)).contains("Bonjour"))
        let pages = try await FileConverter.convert(pdf, to: .png)
        let images = try FileManager.default.contentsOfDirectory(atPath: pages.path)
        #expect(images.count == document.pageCount)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func videoConvertieEnGIF() async throws {
        // Petite vidéo de 1 s (10 images) écrite avec AVAssetWriter.
        let mov = folder.appendingPathComponent("film.mov")
        let writer = try AVAssetWriter(outputURL: mov, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pixels: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixels)
            let buffer = try #require(pixels)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 20), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)

        var steps: [Double] = []
        let gif = try await FileConverter.convert(mov, to: .gif) { steps.append($0) }
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) >= 5)
        // L'avancement monte jusqu'au bout.
        #expect(steps.last == 1)
        #expect(steps == steps.sorted())
        let mp4 = try await FileConverter.convert(mov, to: .mp4)
        #expect(size(mp4) > 0)
        try? FileManager.default.removeItem(at: folder)
    }
}

struct DropCatcherTests {
    @Test func seulsFichiersEtTexteActiventLaReception() {
        #expect(DropCatcher.isDroppable([.fileURL]))
        #expect(DropCatcher.isDroppable([.string, .rtf]))
        #expect(!DropCatcher.isDroppable([.color]))
    }
}
