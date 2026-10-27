#if DEBUG
import AppKit
import SwiftUI

/// Données fictives des tournages, dans la langue de l'interface (le build Debug suit `-AppleLanguages`).
/// Rien ne vient des données réelles de l'utilisateur (agenda, rappels, notes, captures, presse-papiers).
@MainActor
enum DemoData {
    static let french = Locale.preferredLanguages.first?.hasPrefix("fr") == true
    static func text(_ en: String, _ fr: String) -> String { french ? fr : en }

    /// Pochette inventée : dégradé violet, rose, orange.
    static let artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
        NSGradient(colors: [.systemPurple, .systemPink, .systemOrange])?.draw(in: rect, angle: 45)
        return true
    }

    // MARK: Fichiers

    /// Dossier jetable des fichiers de démonstration (vidé au début de chaque tournage).
    static let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notchkit-demo", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Fichiers créés à la demande : images et PDF réels (aperçus lisibles), sinon fichiers vides.
    static func files(_ names: [String]) -> [URL] {
        names.map { name in
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: contents(for: url))
            }
            return url
        }
    }

    private static func contents(for url: URL) -> Data? {
        let hue = CGFloat(abs(url.lastPathComponent.hashValue % 360)) / 360
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff":
            let image = NSImage(size: NSSize(width: 800, height: 600), flipped: false) { rect in
                NSGradient(colors: [NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1),
                                    NSColor(hue: (hue + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.8,
                                            brightness: 0.6, alpha: 1)])?.draw(in: rect, angle: 35)
                return true
            }
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: url.pathExtension.lowercased() == "png" ? .png : .jpeg, properties: [:])
        case "pdf":
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let consumer = CGDataConsumer(data: data),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
            pdf.beginPDFPage(nil)
            pdf.setFillColor(NSColor(hue: hue, saturation: 0.6, brightness: 0.95, alpha: 1).cgColor)
            pdf.fill(CGRect(x: 0, y: 642, width: 595, height: 200))
            pdf.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
            for line in 0..<14 { pdf.fill(CGRect(x: 60, y: 580 - line * 34, width: line % 4 == 3 ? 300 : 475, height: 12)) }
            pdf.endPDFPage()
            pdf.closePDF()
            return data as Data
        case "txt", "md":
            return Data(text("Notchkit — launch notes", "Notchkit — notes de lancement").utf8)
        default:
            return Data()
        }
    }

    // MARK: Contenus

    static var weather: WeatherSnapshot {
        let now = Calendar.current.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
        let hours = (0..<6).map { offset in
            WeatherSnapshot.Hour(date: now.addingTimeInterval(Double(offset) * 3600),
                                 temperature: 21 + Double([0, 1, 2, 2, 1, 0][offset]), code: [0, 1, 1, 2, 2, 3][offset],
                                 isDay: true)
        }
        return WeatherSnapshot(temperature: 21, apparentTemperature: 20, code: 1, isDay: true, high: 24, low: 14,
                               precipitationChance: 5, hours: hours, locationName: "Paris", fetchedAt: Date())
    }

    static var events: [CalendarEvent] {
        let now = Date()
        func from(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        return [
            CalendarEvent(id: "1", title: text("Design review", "Revue design"), start: from(12), end: from(57), isAllDay: false,
                          color: .orange, calendarTitle: "Work"),
            CalendarEvent(id: "2", title: text("Lunch with Sam", "Déjeuner avec Sam"), start: from(95), end: from(155),
                          isAllDay: false, color: .green, calendarTitle: "Personal"),
            CalendarEvent(id: "3", title: text("Ship Notchkit", "Publier Notchkit"), start: from(240), end: from(270),
                          isAllDay: false, color: .purple, calendarTitle: "Work"),
        ]
    }

    static var reminders: [TodoItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return [
            TodoItem(id: "r1", title: text("Record the launch video", "Tourner la vidéo de lancement"),
                     due: today.addingTimeInterval(17 * 3600), priority: 1, listColor: .orange),
            TodoItem(id: "r2", title: text("Reply to Léa", "Répondre à Léa"), due: today.addingTimeInterval(18 * 3600),
                     priority: 0, listColor: .blue),
            TodoItem(id: "r3", title: text("Buy coffee beans", "Acheter du café"), due: nil, priority: 0, listColor: .green),
        ]
    }

    static var clipboard: [ClipboardItem] {
        [
            ClipboardItem(content: .text("github.com/Mycate39/Notchkit"), sourceApp: "Safari"),
            ClipboardItem(content: .text(text("Meeting moved to 3 PM", "Réunion décalée à 15 h")), sourceApp: "Messages"),
            ClipboardItem(content: .text("#FF9E29"), sourceApp: "Figma"),
            ClipboardItem(content: .text("npm run build"), sourceApp: "Terminal"),
        ]
    }

    static var notes: String {
        text("Ideas for the launch\n• 30-second video\n• Post on Reddit\n• Thank the beta testers",
             "Idées pour le lancement\n• Vidéo de 30 secondes\n• Poster sur Reddit\n• Remercier les bêta-testeurs")
    }

    static var screenTime: ScreenTimeLog {
        var log = ScreenTimeLog()
        let day = ActivityClock.dayKey(Date())
        for (app, minutes) in [("com.apple.dt.Xcode", 142.0), ("com.apple.Safari", 76), ("com.apple.Music", 48),
                               ("com.apple.MobileSMS", 21), ("com.apple.Notes", 12)] {
            log.add(minutes * 60, app: app, day: day)
        }
        return log
    }

    static var translation: (source: String, result: String) {
        french ? ("Where is the nearest train station?", "Où est la gare la plus proche ?")
            : ("Où est la gare la plus proche ?", "Where is the nearest train station?")
    }
}
#endif
