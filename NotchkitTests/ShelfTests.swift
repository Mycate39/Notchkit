import Foundation
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
