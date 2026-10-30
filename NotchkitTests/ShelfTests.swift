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
        // Pas de fichier caché : le point du début est retiré.
        #expect(ShelfTextClipping.fileName(for: ".bashrc") == "bashrc.txt")
        #expect(ShelfTextClipping.fileName(for: "...") == "Texte.txt")
    }

    @Test func seulsLesTextesDeposesSontEffaces() {
        let folder = URL(fileURLWithPath: "/Users/x/Library/Application Support/Notchkit/Shelf", isDirectory: true)
        #expect(ShelfTextClipping.isClipping(folder.appendingPathComponent("Idée.txt"), in: folder))
        #expect(!ShelfTextClipping.isClipping(URL(fileURLWithPath: "/Users/x/Documents/Idée.txt"), in: folder))
        #expect(!ShelfTextClipping.isClipping(folder.appendingPathComponent("sous/Idée.txt"), in: folder))
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
        // Un fichier de même nom, venu d'un autre dossier : les deux sont dans l'archive.
        let other = folder.appendingPathComponent("autre", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let homonym = other.appendingPathComponent("a.txt")
        try "trois".write(to: homonym, atomically: true, encoding: .utf8)
        let archive = try #require(await FileActions.zip([a, b, homonym]))
        #expect(archive.pathExtension == "zip")
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        listing.arguments = ["-1", archive.path]
        let pipe = Pipe()
        listing.standardOutput = pipe
        try listing.run()
        listing.waitUntilExit()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        #expect(Set(names).isSuperset(of: ["Archive/a.txt", "Archive/b.txt", "Archive/a 2.txt"]))

        // Un dossier seul garde son nom entier.
        let project = folder.appendingPathComponent("Projet.v2", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "x".write(to: project.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)
        let single = try #require(await FileActions.zip([project]))
        #expect(single.lastPathComponent == "Projet.v2.zip")
    }

    @Test func nomsDansLArchiveSansDoublon() {
        let urls = ["/a/Note.txt", "/b/note.txt", "/c/Note.txt", "/d/Dossier"].map { URL(fileURLWithPath: $0) }
        #expect(FileActions.archiveNames(for: urls) == ["Note.txt", "note 2.txt", "Note 3.txt", "Dossier"])
    }
}

/// Dépôt sur l'étagère : nouveaux fichiers en tête, fichier redéposé remis en tête pour 5 minutes.
struct ShelfDropTests {
    @Test func fichierRedeposeRepartPourCinqMinutes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchkit-shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try ["a.txt", "b.txt", "c.txt"].map { name -> URL in
            let url = folder.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = try #require(ShelfItem(url: files[0], date: start))
        let b = try #require(ShelfItem(url: files[1], date: start.addingTimeInterval(10)))
        let later = start.addingTimeInterval(200)

        // b est déjà là ; c est nouveau ; c déposé deux fois ne compte qu'une fois.
        let drop = ShelfModule.dropped([files[2], files[1], files[2]], onto: [b, a], at: later) { $0.resolvedURL() }
        #expect(drop.items.map(\.name) == ["c.txt", "b.txt", "a.txt"])
        #expect(drop.again == [b.id])
        #expect(drop.count == 2)
        #expect(drop.items[1].id == b.id)
        #expect(drop.items[1].addedAt == later)
        #expect(drop.items[2].addedAt == start)

        // Rien de neuf : rien ne change.
        #expect(ShelfModule.dropped([], onto: [a], at: later) { $0.resolvedURL() }.count == 0)
    }
}

/// Étagère : cinq minutes pour récupérer un fichier, fichiers montrés dans la bulle.
struct ShelfRetentionTests {
    @Test func fichiersRetiresApresCinqMinutes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let start = Date()
        let old = try #require(ShelfItem(url: file, date: start.addingTimeInterval(-ShelfModule.retention - 1)))
        let recent = try #require(ShelfItem(url: file, date: start.addingTimeInterval(-60)))
        #expect(ShelfModule.expired([old, recent], at: start) == [old])
        #expect(ShelfModule.expired([recent], at: start.addingTimeInterval(4 * 60)) == [recent])
    }

    @Test func largeurDeLaBulleSelonLeNombreDeFichiers() {
        #expect(ShelfBubbleFiles.width(count: 1) < ShelfBubbleFiles.width(count: 3))
        // Au-delà de trois fichiers, seul « +N » s'ajoute.
        #expect(ShelfBubbleFiles.width(count: 9) == ShelfBubbleFiles.width(count: 4))
    }
}
