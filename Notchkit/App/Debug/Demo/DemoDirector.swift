#if DEBUG
import AppKit
import SwiftUI

/// Tournage de démonstration : joue un scénario minuté sur la vraie encoche et l'enregistre.
///
/// Lancer le build Debug avec `NOTCHKIT_DEMO=/chemin/scenario.json` (et, au besoin,
/// `NOTCHKIT_DEMO_OUTPUT=/dossier`). Produit `notch.mov` (ProRes 4444, fond transparent) et
/// `timeline.json` (zone filmée, instants réels de chaque étape), puis quitte. Les actions passent
/// par les vrais chemins de l'app autant que possible : aperçu du déverrouillage, minuteurs des
/// activités en direct, événements de hooks de Claude Code, dépliage et survol de `NotchViewModel`.
@MainActor
final class DemoDirector {
    private let scenarioURL: URL
    private let outputURL: URL
    private let viewModel: NotchViewModel
    private let manager: ModuleManager
    private let window: NotchWindowController
    private let settings: SettingsStore
    private let recorder = DemoRecorder()
    /// Préférences des modules (domaine standard) d'avant le tournage, remises à la fin.
    private var savedDefaults: [String: Any]?
    private var log: [[String: Any]] = []
    private static let sessionID = "notchkit-demo"

    init(scenarioURL: URL, outputURL: URL, viewModel: NotchViewModel, manager: ModuleManager, window: NotchWindowController,
         settings: SettingsStore) {
        self.scenarioURL = scenarioURL
        self.outputURL = outputURL
        self.viewModel = viewModel
        self.manager = manager
        self.window = window
        self.settings = settings
    }

    func run() async {
        let scenario: DemoScenario
        do {
            scenario = try JSONDecoder().decode(DemoScenario.self, from: Data(contentsOf: scenarioURL))
        } catch {
            return report("DEMO-ERREUR scénario illisible : \(error)")
        }
        let panel = window.debugPanel
        guard let screen = panel.screen else { return report("DEMO-ERREUR aucun écran") }

        // Zone filmée : haut de l'écran de l'encoche, centrée horizontalement (coordonnées de l'écran).
        let region = CGRect(x: (screen.frame.width - scenario.region.width) / 2, y: 0,
                            width: scenario.region.width, height: scenario.region.height)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        do {
            try await recorder.start(window: panel, region: region, scale: screen.backingScaleFactor,
                                     fps: scenario.fps, to: outputURL.appendingPathComponent("notch.mov"))
        } catch {
            return report("DEMO-ERREUR enregistrement impossible (autorisation « Enregistrement de l'écran » ?) : \(error)")
        }

        // Aucun morceau tant que le scénario n'en lance pas un (la musique réelle de l'utilisateur est ignorée).
        music?.debugPinNowPlaying(nil)
        prepareModules()
        let start = ContinuousClock.now
        // Instant du début (horloge murale) : pour caler des événements extérieurs, comme les
        // changements de bureau d'un diagnostic, sur la vidéo.
        let startedAt = Date().timeIntervalSince1970
        func elapsed() -> Double {
            let duration = ContinuousClock.now - start
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        for step in scenario.steps {
            let wait = step.at - elapsed()
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            perform(step)
            log.append(["at": elapsed(), "planned": step.at, "do": step.action])
        }
        let rest = scenario.duration - elapsed()
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
        await recorder.stop()
        cleanUp()

        let timeline: [String: Any] = [
            "fps": scenario.fps,
            "duration": scenario.duration,
            "scale": screen.backingScaleFactor,
            "startedAt": startedAt,
            // Zone filmée et écran, en points : le centre de la zone est le centre de l'encoche.
            "region": ["width": region.width, "height": region.height],
            "screen": ["width": screen.frame.width, "height": screen.frame.height],
            "steps": log,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: timeline, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outputURL.appendingPathComponent("timeline.json"))
        }
        report("DEMO-OK \(outputURL.path)")
    }

    // MARK: - Actions

    private func perform(_ step: DemoScenario.Step) {
        switch step.action {
        case "unlock":
            unlock?.preview("faceID")
        case "touchID":
            unlock?.preview("touchID")
        case "music.play", "music.pause":
            var info = NowPlayingInfo(
                origin: .mediaRemote, title: step.title ?? music?.nowPlaying?.title ?? "danker",
                artist: step.artist ?? music?.nowPlaying?.artist ?? "Gabester",
                isPlaying: step.action == "music.play", duration: 204, elapsed: 42, timestamp: Date())
            info.artwork = DemoData.artwork
            info.artworkHash = 1
            music?.debugPinNowPlaying(info)
        case "timer.start":
            activities?.startTimer(minutes: step.minutes ?? 5)
        case "timer.pause":
            if let id = lastTimerID { activities?.togglePause(id) }
        case "timer.stop":
            if let id = lastTimerID { activities?.remove(id) }
        case "bubble.hover":
            viewModel.hoverBubbleControls(step.module ?? LiveActivitiesModule.descriptor.id, part: .bubble, inside: true)
        case "bubble.leave":
            viewModel.hoverBubbleControls(step.module ?? LiveActivitiesModule.descriptor.id, part: .bubble, inside: false)
        case "expand":
            if let module = step.module { viewModel.expand(showing: module) } else { viewModel.expand() }
        case "collapse":
            viewModel.collapse()
        case "fullscreen":
            window.debugSetHiddenForFullScreen(step.hidden ?? true)
        case "lock":
            viewModel.setScreenLocked(true)
        case "unlock.screen":
            viewModel.setScreenLocked(false)
        case "claude.work":
            claudeEvent(step, ["hook_event_name": "UserPromptSubmit", "prompt": step.prompt ?? "Update the title"])
            claudeEvent(step, ["hook_event_name": "PreToolUse", "tool_name": "Edit", "tool_input": [
                "file_path": filePath(step), "old_string": step.old ?? "<h1>Hello</h1>", "new_string": step.new ?? "<h1>Hello, notch!</h1>",
            ]])
        case "claude.ask":
            let command = step.command ?? "npm test"
            claudeEvent(step, ["hook_event_name": "PermissionRequest", "tool_name": "Bash",
                               "tool_input": ["command": command, "description": step.description ?? "Run \(command) in project folder"],
                               "permission_suggestions": [["behavior": "allow", "type": "addRules"]],
                               ClaudeHookServer.waitKey: true])
        case "claude.allow":
            claude?.decidePermission(Self.sessionID, allow: true)
            claudeEvent(step, ["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": step.command ?? "npm test"]])
        case "claude.done":
            claudeEvent(step, ["hook_event_name": "Stop"])
        case "page":
            withAnimation(NotchLayout.spring) { viewModel.selectedPage = step.page ?? 0 }
        case "stopwatch.start":
            activities?.startStopwatch()
        case "pomodoro.start":
            activities?.startPomodoro()
        case "alarm.start":
            activities?.startAlarm(hour: step.hour ?? 7, minute: Int(step.minutes ?? 0))
        case "activities.clear":
            activities?.activities.map(\.id).forEach { activities?.remove($0) }
        case "hud.volume", "hud.brightness":
            hud?.debugShow(step.action == "hud.volume" ? .volume : .brightness, level: Float(step.level ?? 0.6))
        case "airpods.connect":
            guard let airPods else { break }
            let device = HeadphoneDevice(id: 1, uid: "demo-airpods", name: step.title ?? "AirPods Pro", isDefaultOutput: true)
            airPods.debugSetDevices([device], bluetooth: [
                BluetoothDeviceInfo(name: device.name, address: "", minorType: "Headphones",
                                    battery: BluetoothBattery(left: 92, right: 88, caseLevel: 64, main: nil)),
            ])
            viewModel.present(AirPodsAlerts.connected(device, module: airPods))
        case "battery.plug":
            battery?.debugSetState(BatteryState(level: Int(step.level ?? 62), isCharging: true, isCharged: false,
                                                powerSource: .ac, minutesToFull: 75))
            battery?.simulate(.pluggedIn)
        case "battery.low":
            battery?.debugSetState(BatteryState(level: Int(step.level ?? 10), isCharging: false, isCharged: false,
                                                powerSource: .battery))
            battery?.simulate(.low(threshold: Int(step.level ?? 10)))
        case "weather.set":
            weather?.debugSetSnapshot(DemoData.weather)
        case "calendar.set":
            calendar?.debugSetEvents(DemoData.events)
        case "todo.set":
            todo?.debugSetItems(DemoData.reminders)
        case "clipboard.set":
            clipboard?.debugSetItems(DemoData.clipboard)
        case "notes.set":
            notes?.debugSetText(step.value ?? DemoData.notes)
        case "screentime.set":
            screenTime?.debugSetLog(DemoData.screenTime)
        case "health.set":
            health?.debugSet(pauses: 3, glasses: 5, activeMinutes: 38)
        case "monitor.sample":
            SystemSampler.shared.debugSampleNow()
        case "translation.set":
            let pair = DemoData.translation
            translation?.debugSetResult(source: pair.source, result: pair.result)
        case "screenshot":
            screenshots?.debugAdd(DemoData.files([step.value ?? DemoData.text("Screenshot.png", "Capture.png")])[0])
        case "shelf.add":
            shelf?.add(DemoData.files(step.items ?? ["Mockup.pdf"]))
        case "drag.move":
            viewModel.fileDragMoved(normalizedX: step.level ?? 0.2)
        case "drag.end":
            viewModel.fileDragEnded()
        case "drop":
            viewModel.dropFiles(DemoData.files(step.items ?? ["Mockup.pdf"]), normalizedX: step.level ?? 0.2)
        case "converter.done":
            let names = step.items ?? ["Photo.jpg"]
            converter?.debugSetResults(DemoData.files(names))
            viewModel.present(ConverterAlerts.finished(count: names.count, succeeded: true))
        case "download.start":
            guard let downloads else { break }
            let id = downloads.debugStart(title: step.title ?? "Notchkit 2.0")
            let length = step.level ?? 4
            Task { @MainActor in
                for tick in 1...Int(length * 10) {
                    try? await Task.sleep(for: .milliseconds(100))
                    downloads.debugProgress(id, Double(tick) / (length * 10))
                }
            }
        case "gamemode":
            gameMode?.debugSet(active: !(step.hidden ?? false), fps: Int(step.level ?? 120))
        case "antisleep":
            toggles?.toggleAntiSleep()
        case "claude.question":
            let options = (step.items ?? ["A", "B"]).map { ["label": $0] }
            claudeEvent(step, ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
                               "tool_input": ["questions": [["question": step.prompt ?? "?", "header": step.title ?? "",
                                                              "options": options, "multiSelect": false]]],
                               ClaudeHookServer.waitKey: true])
        case "claude.answer":
            claude?.answerQuestions(Self.sessionID, selections: [step.prompt ?? "?": [step.value ?? ""]])
        case "settings.accent", "settings.background", "settings.size", "settings.mascot", "settings.layout",
             "settings.animation", "settings.custom":
            var setup = DemoScenario.Setup()
            switch step.action {
            case "settings.accent": setup.accent = step.value
            case "settings.background": setup.background = step.value
            case "settings.size": setup.size = step.value
            case "settings.mascot": setup.mascot = step.value
            case "settings.animation": setup.animation = step.value
            case "settings.custom": setup.customSize = step.value
            default: setup.pages = step.pages; setup.sizes = step.sizes
            }
            var updated = settings.settings
            DemoSettings.apply(setup, to: &updated)
            withAnimation(NotchLayout.spring) { settings.settings = updated }
        case "end":
            break
        default:
            report("DEMO-AVERTISSEMENT action inconnue : \(step.action)")
        }
    }

    /// Envoie un événement de hook au module Claude Code, comme le ferait Claude Code par HTTP.
    private func claudeEvent(_ step: DemoScenario.Step, _ fields: [String: Any]) {
        let project = step.project ?? "website"
        var json: [String: Any] = ["session_id": Self.sessionID, "cwd": "/Users/demo/Documents/\(project)"]
        json.merge(fields) { _, new in new }
        claude?.handle(json, reply: HookReply { _ in })
    }

    private func filePath(_ step: DemoScenario.Step) -> String {
        "/Users/demo/Documents/\(step.project ?? "website")/\(step.file ?? "index.html")"
    }

    /// Avant de filmer : sauvegarde des préférences des modules, étagère et presse-papiers vides
    /// (on ne montre jamais les fichiers ni le texte de l'utilisateur).
    private func prepareModules() {
        if let domain = Bundle.main.bundleIdentifier {
            savedDefaults = UserDefaults.standard.persistentDomain(forName: domain)
        }
        // Agenda et météo : plus de lecture des données réelles (EventKit, position).
        calendar?.stop()
        weather?.stop()
        shelf?.clear()
        clipboard?.debugSetItems([])
        notes?.debugSetText("")
        screenTime?.debugSetLog(ScreenTimeLog())
        todo?.debugSetItems([])
        calendar?.debugSetEvents([])
    }

    /// Remet l'app dans son état normal avant de quitter.
    private func cleanUp() {
        viewModel.setScreenLocked(false)
        window.debugSetHiddenForFullScreen(false)
        music?.debugUnpin()
        gameMode?.debugSet(active: false, fps: nil)
        if toggles?.isAntiSleepOn == true { toggles?.toggleAntiSleep() }
        // Ce que les modules ont écrit pendant le tournage (étagère, santé…) est effacé.
        if let domain = Bundle.main.bundleIdentifier, let savedDefaults {
            UserDefaults.standard.setPersistentDomain(savedDefaults, forName: domain)
        }
    }

    private var lastTimerID: String? {
        activities?.activities.last(where: { $0.kind == .timer })?.id
    }

    private var music: MusicModule? { manager.module(for: MusicModule.descriptor.id) as? MusicModule }
    private var activities: LiveActivitiesModule? { manager.module(for: LiveActivitiesModule.descriptor.id) as? LiveActivitiesModule }
    private var claude: ClaudeModule? { manager.module(for: ClaudeModule.descriptor.id) as? ClaudeModule }
    private var unlock: UnlockModule? { manager.module(for: UnlockModule.descriptor.id) as? UnlockModule }
    private var hud: SystemHUDModule? { module(SystemHUDModule.self) }
    private var airPods: AirPodsModule? { module(AirPodsModule.self) }
    private var battery: BatteryModule? { module(BatteryModule.self) }
    private var weather: WeatherModule? { module(WeatherModule.self) }
    private var calendar: CalendarModule? { module(CalendarModule.self) }
    private var todo: TodoModule? { module(TodoModule.self) }
    private var clipboard: ClipboardModule? { module(ClipboardModule.self) }
    private var notes: NotesModule? { module(NotesModule.self) }
    private var screenTime: ScreenTimeModule? { module(ScreenTimeModule.self) }
    private var health: HealthModule? { module(HealthModule.self) }
    private var translation: TranslationModule? { module(TranslationModule.self) }
    private var screenshots: ScreenshotsModule? { module(ScreenshotsModule.self) }
    private var shelf: ShelfModule? { module(ShelfModule.self) }
    private var converter: ConverterModule? { module(ConverterModule.self) }
    private var downloads: VideoDownloadModule? { module(VideoDownloadModule.self) }
    private var gameMode: GameModeModule? { module(GameModeModule.self) }
    private var toggles: TogglesModule? { module(TogglesModule.self) }

    private func module<M: NotchModule>(_ type: M.Type) -> M? { manager.module(for: M.descriptor.id) as? M }

    private func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
