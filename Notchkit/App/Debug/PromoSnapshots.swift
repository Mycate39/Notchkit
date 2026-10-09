#if DEBUG
import AppKit
import EventKit
import SwiftUI

/// Images de démonstration pour la vidéo de présentation : les vrais composants de l'app,
/// alimentés avec des données fictives. Les modules sont créés à part (jamais démarrés,
/// rien n'est enregistré). Rendu dans `<dossier>/promo/`, fond transparent, à l'échelle 4.
@MainActor
enum PromoSnapshots {
    /// Encoche d'un MacBook Pro 14 pouces (en points).
    private static let notchSize = CGSize(width: 185, height: 32)
    /// Largeur d'une carte de poids 1 dans l'encoche dépliée (taille standard, 4 par page).
    private static let unitWidth: CGFloat = 148
    private static let cardHeight: CGFloat = 140
    /// Données fictives dans la langue de l'interface.
    private static let french = Locale.preferredLanguages.first?.hasPrefix("fr") == true
    private static func text(_ en: String, _ fr: String) -> String { french ? fr : en }

    /// Collecte les alertes que les modules présentent.
    private final class AlertBox { var alerts: [NotchAlert] = [] }

    static func renderAll(to directory: URL) {
        let dir = directory.appendingPathComponent("promo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let box = AlertBox()
        let context = ModuleContext(presentAlert: { box.alerts.append($0) }, openSettings: {}, holdExpanded: { _ in })
        func lastAlert() -> NotchAlert? { defer { box.alerts.removeAll() }; return box.alerts.last }
        func file(_ name: String) -> URL { dir.appendingPathComponent("\(name).png") }

        // Musique : activité compacte, pilule et grande carte.
        let music = MusicModule(context: context)
        var info = NowPlayingInfo(origin: .appleMusic, title: "Entropy", artist: "Beach Bunny", isPlaying: true)
        info.duration = 221
        info.elapsed = 170
        info.timestamp = Date()
        info.artwork = artwork
        info.artworkHash = 1
        music.debugSetNowPlaying(info)
        save(compact(music.compactLeading(), music.compactTrailing()), to: file("01-musique-compacte"))
        save(island(music.compactLeading(), music.compactTrailing()), to: file("01-musique-pilule"))
        save(card(music.expandedView(), weight: 2), to: file("01-musique-carte"))

        // Minuteur.
        let activities = LiveActivitiesModule(context: context)
        activities.startTimer(seconds: 299)
        save(compact(activities.compactLeading(), activities.compactTrailing()), to: file("02-minuteur-compact"))
        save(card(activities.expandedView(), weight: 1.5), to: file("02-minuteur-carte"))

        // Claude Code : au travail, puis la conversation avec le champ de réponse.
        let claude = ClaudeModule(context: context)
        claude.debugSetDemo(events: claudeWorkingEvents)
        save(compact(claude.compactLeading(), claude.compactTrailing()), to: file("03-claude-compact"))
        save(card(claude.expandedView(), weight: 2), to: file("03-claude-travail"))
        claude.debugSetDemo(events: claudeWorkingEvents, conversation: claudeConversation)
        save(card(claude.expandedView(), weight: 2), to: file("03-claude-conversation"))

        // AirPods : alerte de connexion et carte.
        let airPods = AirPodsModule(context: context)
        let device = HeadphoneDevice(id: 1, uid: "demo-airpods", name: "AirPods Pro", isDefaultOutput: true)
        airPods.debugSetDevices([device], bluetooth: [
            BluetoothDeviceInfo(name: "AirPods Pro", address: "", minorType: "Headphones",
                                battery: BluetoothBattery(left: 92, right: 88, caseLevel: 64, main: nil)),
        ])
        let connected = AirPodsAlerts.connected(device, module: airPods)
        save(compact(connected.leading, connected.trailing), to: file("04-airpods-alerte"))
        save(card(airPods.expandedView(), weight: 1.5), to: file("04-airpods-carte"))

        // Batterie : alerte de branchement et carte.
        let battery = BatteryModule(context: context)
        let charging = BatteryState(level: 100, isCharging: false, isCharged: true, powerSource: .ac)
        battery.debugSetState(charging)
        let plugged = BatteryAlertFactory.alert(for: .pluggedIn, state: charging)
        save(compact(plugged.leading, plugged.trailing), to: file("05-batterie-alerte"))
        save(card(battery.expandedView(), weight: 1), to: file("05-batterie-carte"))

        // Étagère : deux fichiers (créés dans le dossier temporaire, jamais enregistrés).
        let shelf = ShelfModule(context: context)
        shelf.debugSetItems(demoFiles.compactMap { ShelfItem(url: $0) })
        save(card(shelf.expandedView(), weight: 2), to: file("06-etagere-carte"))

        // Presse-papiers, météo, calendrier, horloge.
        let clipboard = ClipboardModule(context: context)
        clipboard.debugSetItems([
            ClipboardItem(content: .text("github.com/Mycate39/Notchkit"), sourceApp: "Safari"),
            ClipboardItem(content: .text(text("Lunch at 12:30?", "Déjeuner à 12 h 30 ?")), sourceApp: "Messages"),
            ClipboardItem(content: .text("#FF9E29"), sourceApp: "Figma"),
        ])
        save(card(clipboard.expandedView(), weight: 2), to: file("07-presse-papiers-carte"))

        let weather = WeatherModule(context: context)
        weather.debugSetSnapshot(demoWeather)
        save(card(weather.expandedView(), weight: 1.5), to: file("07-meteo-carte"))

        let calendar = CalendarModule(context: context)
        calendar.debugSetEvents(demoEvents)
        save(card(calendar.expandedView(), weight: 2), to: file("07-calendrier-carte"))

        let clock = ClockModule(context: context)
        save(card(clock.expandedView(), weight: 1), to: file("07-horloge-carte"))

        // Encoche dépliée complète : horloge, météo, calendrier (une page de 4,5 → 4).
        save(expanded([(clock.expandedView(), 1), (weather.expandedView(), 1.5), (calendar.expandedView(), 1.5)]),
             to: file("08-encoche-depliee"))
        save(expanded([(music.expandedView(), 2), (battery.expandedView(), 1), (activities.expandedView(), 1)]),
             to: file("08-encoche-depliee-2"))

        // Indicateur de volume.
        let hud = SystemHUDModule(context: context)
        hud.debugShow(.volume, level: 0.62)
        if let alert = lastAlert() {
            save(compact(alert.leading, alert.trailing, sideWidth: alert.sideWidth), to: file("09-volume"))
        }

        // Modules de la 1.0 (cartes de vérification).
        save(card(TogglesModule(context: context).expandedView(), weight: 2), to: file("10-commutateurs-carte"))
        save(card(CameraModule(context: context).expandedView(), weight: 1.5), to: file("11-webcam-carte"))
        save(card(DayProgressModule(context: context).expandedView(), weight: 2), to: file("12-journee-carte"))
        save(card(NotesModule(context: context).expandedView(), weight: 2), to: file("13-notes-carte"))
        let multi = LiveActivitiesModule(context: context)
        multi.startStopwatch()
        multi.startPomodoro()
        save(card(multi.expandedView(), weight: 2), to: file("14-activites-carte"))
        SystemSampler.shared.debugSampleNow()
        save(card(SystemMonitorModule(context: context).expandedView(), weight: 2), to: file("15-moniteur-carte"))
        save(card(DashboardModule(context: context).expandedView(), weight: 2), to: file("16-dashboard-carte"))
        save(card(ScreenTimeModule(context: context).expandedView(), weight: 2), to: file("17-temps-ecran-carte"))
        save(card(HealthModule(context: context).expandedView(), weight: 2), to: file("18-sante-carte"))
        multi.activities.map(\.id).forEach(multi.remove)

        activities.activities.map(\.id).forEach(activities.remove)
        music.debugSetNowPlaying(nil)
        box.alerts.removeAll()
    }

    // MARK: - Mises en forme (reprennent les dimensions de NotchContainerView)

    /// Encoche repliée, de part et d'autre de l'encoche physique.
    private static func compact(_ leading: AnyView?, _ trailing: AnyView?, sideWidth: CGFloat? = nil) -> some View {
        let side = sideWidth ?? NotchLayout.compactSideWidth
        let ear = NotchLayout.earRadius
        let radii = NotchLayout.cornerRadii(for: .notch, isExpanded: false, height: notchSize.height)
        let contentHeight = min(22, max(14, notchSize.height - 4))
        return HStack(spacing: 0) {
            leading.frame(maxHeight: contentHeight).frame(width: side - 12, alignment: .leading)
            Spacer(minLength: 0)
            trailing.frame(maxHeight: contentHeight).frame(width: side - 12, alignment: .trailing)
        }
        .padding(.horizontal, ear + 10)
        .frame(width: notchSize.width + side * 2 + ear * 2, height: notchSize.height)
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(.white)
        .background(NotchShape(earRadius: ear, topCornerRadius: radii.top, bottomCornerRadius: radii.bottom).fill(.black))
        .environment(\.colorScheme, .dark)
        .tint(StandBy.amber)
    }

    /// Île flottante (Mac sans encoche).
    private static func island(_ leading: AnyView?, _ trailing: AnyView?) -> some View {
        let height = 20 + NotchLayout.islandExtraHeight
        let content = (height * 0.6).rounded()
        return HStack(spacing: 0) {
            leading.frame(height: content)
            Spacer(minLength: 0)
            trailing.frame(height: content)
        }
        .padding(.horizontal, (height - content) / 2 + 3)
        .frame(width: (height * NotchLayout.islandAspectRatio).rounded(), height: height)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .background(Capsule().fill(.black))
        .environment(\.colorScheme, .dark)
        .tint(StandBy.amber)
    }

    /// Une carte de l'encoche dépliée, à sa taille réelle.
    private static func card(_ view: AnyView, weight: CGFloat) -> some View {
        view
            .environment(\.widgetSize, size(for: weight))
            .frame(width: unitWidth * weight, height: cardHeight)
            .notchCard()
            .padding(8)
            .background(.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .tint(StandBy.amber)
    }

    /// Encoche dépliée : panneau noir aux coins du bas arrondis, cartes côte à côte.
    private static func expanded(_ cards: [(AnyView, CGFloat)]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, entry in
                entry.0
                    .environment(\.widgetSize, size(for: entry.1))
                    .frame(width: unitWidth * entry.1, height: cardHeight)
                    .notchCard()
            }
        }
        .padding(.top, 36)
        .padding([.horizontal, .bottom], 18)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: NotchLayout.expandedCornerRadius,
                                           bottomTrailingRadius: NotchLayout.expandedCornerRadius,
                                           style: .continuous).fill(.black))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .tint(StandBy.amber)
    }

    private static func size(for weight: CGFloat) -> WidgetSize {
        switch weight {
        case ..<1: .mini
        case ..<1.5: .small
        case ..<2: .medium
        default: .large
        }
    }

    /// Rendu par une vraie fenêtre AppKit hors écran : contrairement à `ImageRenderer`, les vues AppKit
    /// intégrées (égaliseur, étoile de Claude, champs de texte, listes défilantes) apparaissent.
    private static func save(_ view: some View, to url: URL) {
        let scale: CGFloat = 4
        let hosting = NSHostingView(rootView: AnyView(view.fixedSize()))
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Laisse les animations d'apparition se terminer (jauge, éclair, anneaux).
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.contentView = nil
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    // MARK: - Données fictives

    private static let artwork = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
        NSGradient(colors: [.systemPurple, .systemPink, .systemOrange])?.draw(in: rect, angle: 45)
        return true
    }

    private static func claudeEvent(_ name: String, tool: String? = nil, input: [String: String] = [:],
                                    prompt: String? = nil) -> ClaudeHookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": "demo", "cwd": "/Users/demo/Notchkit"]
        if let tool { json["tool_name"] = tool; json["tool_input"] = input }
        if let prompt { json["prompt"] = prompt }
        return ClaudeHookEvent(json: json)!
    }

    private static var claudeWorkingEvents: [ClaudeHookEvent] {
        [
            claudeEvent("UserPromptSubmit", prompt: claudePrompt),
            claudeEvent("PreToolUse", tool: "Read", input: ["file_path": "/Users/demo/Notchkit/NotchViewModel.swift"]),
            claudeEvent("PostToolUse", tool: "Read", input: ["file_path": "/Users/demo/Notchkit/NotchViewModel.swift"]),
            claudeEvent("PreToolUse", tool: "Edit", input: ["file_path": "/Users/demo/Notchkit/NotchView.swift"]),
        ]
    }

    private static var claudePrompt: String {
        text("Make the notch spring open on hover", "Fais s'ouvrir l'encoche au survol avec un ressort")
    }

    private static var claudeConversation: [ClaudeChatEntry] {
        [
            ClaudeChatEntry(id: "1", role: .user, text: claudePrompt),
            ClaudeChatEntry(id: "2", role: .claude,
                            text: text("Found it, adding the spring.",
                                       "Trouvé, j'ajoute le ressort.")),
        ]
    }

    private static var demoFiles: [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchkit-promo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ["Mockup.pdf", "Keynote.key", "Photo.heic"].map { name in
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: Data()) }
            return url
        }
    }

    private static var demoWeather: WeatherSnapshot {
        let now = Calendar.current.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
        let hours = (0..<6).map { offset in
            WeatherSnapshot.Hour(date: now.addingTimeInterval(Double(offset) * 3600),
                                 temperature: 18 + Double([0, 1, 2, 2, 1, 0][offset]), code: [1, 1, 2, 2, 3, 3][offset],
                                 isDay: true)
        }
        return WeatherSnapshot(temperature: 18, apparentTemperature: 17, code: 2, isDay: true, high: 21, low: 12,
                               precipitationChance: 10, hours: hours, locationName: "Paris", fetchedAt: Date())
    }

    private static var demoEvents: [CalendarEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ hour: Double) -> Date { today.addingTimeInterval(hour * 3600) }
        return [
            CalendarEvent(id: "1", title: text("Standup", "Point d'équipe"), start: at(10), end: at(10.25), isAllDay: false,
                          color: .orange, calendarTitle: "Work"),
            CalendarEvent(id: "2", title: text("Design review", "Revue design"), start: at(14.5), end: at(15.5), isAllDay: false,
                          color: .blue, calendarTitle: "Work"),
            CalendarEvent(id: "3", title: text("Gym", "Sport"), start: at(18.5), end: at(19.5), isAllDay: false,
                          color: .green, calendarTitle: "Personal"),
        ]
    }
}
#endif
