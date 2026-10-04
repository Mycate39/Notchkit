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
