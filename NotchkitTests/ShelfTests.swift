import Foundation
import ImageIO
import Testing
@testable import Notchkit

struct DropZoneTests {
    @Test func etagereAGaucheAirDropADroite() {
        #expect(DropZone.zone(atNormalizedX: 0.2, shelfAvailable: true) == .shelf)
        #expect(DropZone.zone(atNormalizedX: 0.8, shelfAvailable: true) == .airDrop)
        #expect(DropZone.zone(atNormalizedX: 0.2, shelfAvailable: false) == .airDrop)
    }
}

struct ShelfItemTests {
    @Test func signetRetrouveLeFichierRenomme() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("rapport.txt")
        try Data("test".utf8).write(to: original)
        let item = try #require(ShelfItem(url: original))
        #expect(item.name == "rapport.txt")

        let renamed = directory.appendingPathComponent("rapport final.txt")
        try FileManager.default.moveItem(at: original, to: renamed)
        #expect(item.resolvedURL()?.lastPathComponent == "rapport final.txt")

        try FileManager.default.removeItem(at: renamed)
        #expect(item.resolvedURL() == nil)
    }

    @Test func encodageDesElements() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let item = try #require(ShelfItem(url: file))
        let decoded = try JSONDecoder().decode([ShelfItem].self, from: JSONEncoder().encode([item]))
        #expect(decoded == [item])
    }
}

struct ScreenshotSessionTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func debutDeSessionLePlusRecent() {
        #expect(ScreenshotSession.start(boot: t0, login: t0.addingTimeInterval(60)) == t0.addingTimeInterval(60))
        #expect(ScreenshotSession.start(boot: t0.addingTimeInterval(90), login: t0) == t0.addingTimeInterval(90))
        #expect(ScreenshotSession.start(boot: nil, login: t0) == t0)
        #expect(ScreenshotSession.start(boot: nil, login: nil) == .distantPast)
    }

    @Test func reconnaitLesEnregistrementsEnFrancaisEtEnAnglais() {
        #expect(ScreenshotSession.isScreenRecording(fileName: "Enregistrement de l’écran 2026-10-09 à 10.00.00.mov"))
        #expect(ScreenshotSession.isScreenRecording(fileName: "Screen Recording 2026-10-09 at 10.00.00.mov"))
        #expect(!ScreenshotSession.isScreenRecording(fileName: "Vacances.mov"))
    }

    @Test func capturesDeLaSessionTrieesSansDoublons() {
        func shot(_ name: String, _ offset: TimeInterval) -> Screenshot {
            Screenshot(url: URL(fileURLWithPath: "/tmp/\(name).png"), date: t0.addingTimeInterval(offset), isVideo: false)
        }
        let items = [shot("a", -10), shot("b", 10), shot("c", 30), shot("b", 10)]
        #expect(ScreenshotSession.sessionItems(items, since: t0).map(\.name) == ["c", "b"])
    }
}

struct ShelfTextClippingTests {
    @Test func nomDuFichierDepuisLaPremiereLigne() {
        #expect(ShelfTextClipping.fileName(for: "Idée : une app\nsuite du texte") == "Idée - une app.txt")
        #expect(ShelfTextClipping.fileName(for: "a/b") == "a-b.txt")
        #expect(ShelfTextClipping.fileName(for: String(repeating: "x", count: 100)).count == 44)
    }
}

struct FileActionsTests {
    @Test func nomLibreAvecSuffixe() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/Photo.jpg", "/tmp/x/Photo 2.jpg"]
        let url = FileActions.uniqueURL(named: "Photo", extension: "jpg", in: folder) { taken.contains($0.path) }
        #expect(url.lastPathComponent == "Photo 3.jpg")
    }

    @Test func zipEtConversionReels() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchkit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let a = folder.appendingPathComponent("a.txt"), b = folder.appendingPathComponent("b.txt")
        try "un".write(to: a, atomically: true, encoding: .utf8)
        try "deux".write(to: b, atomically: true, encoding: .utf8)
        let archive = try #require(await FileActions.zip([a, b]))
        #expect(archive.pathExtension == "zip")
        #expect(FileManager.default.fileExists(atPath: archive.path))

        // Image PNG 4×4 générée, convertie en JPEG.
        let png = folder.appendingPathComponent("carre.png")
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.6, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let destination = try #require(CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(FileActions.isImage(png))
        let jpeg = try #require(await FileActions.convertImage(png, to: .jpeg))
        #expect(jpeg.lastPathComponent == "carre.jpg")
    }
}
