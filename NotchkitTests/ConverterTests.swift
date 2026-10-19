import AppKit
import AVFoundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Notchkit

struct ConverterFormatTests {
    @Test func formatsSelonLaFamille() {
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/photo.jpeg")) == [.png, .heic, .tiff, .pdf])
        #expect(FileConverter.formats(for: URL(fileURLWithPath: "/tmp/son.wav")) == [.m4a, .aiff])
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

    @Test func argumentsAfconvert() {
        #expect(FileConverter.afconvertArguments(for: .wav).contains("WAVE"))
        #expect(FileConverter.afconvertArguments(for: .m4a).contains("aac"))
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
        for target in [ConversionFormat.m4a, .aiff] {
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

        let gif = try await FileConverter.convert(mov, to: .gif)
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) >= 5)
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
