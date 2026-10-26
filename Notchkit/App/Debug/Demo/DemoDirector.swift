#if DEBUG
import AppKit

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
    private let recorder = DemoRecorder()
    private var log: [[String: Any]] = []
    private static let sessionID = "notchkit-demo"

    init(scenarioURL: URL, outputURL: URL, viewModel: NotchViewModel, manager: ModuleManager, window: NotchWindowController) {
        self.scenarioURL = scenarioURL
        self.outputURL = outputURL
        self.viewModel = viewModel
        self.manager = manager
        self.window = window
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
        let start = ContinuousClock.now
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
            music?.debugPinNowPlaying(NowPlayingInfo(
                origin: .mediaRemote, title: step.title ?? music?.nowPlaying?.title ?? "danker",
                artist: step.artist ?? music?.nowPlaying?.artist ?? "Gabester",
                isPlaying: step.action == "music.play", duration: 204, elapsed: 42, timestamp: Date()))
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

    /// Remet l'app dans son état normal avant de quitter.
    private func cleanUp() {
        viewModel.setScreenLocked(false)
        window.debugSetHiddenForFullScreen(false)
        music?.debugUnpin()
    }

    private var lastTimerID: String? {
        activities?.activities.last(where: { $0.kind == .timer })?.id
    }

    private var music: MusicModule? { manager.module(for: MusicModule.descriptor.id) as? MusicModule }
    private var activities: LiveActivitiesModule? { manager.module(for: LiveActivitiesModule.descriptor.id) as? LiveActivitiesModule }
    private var claude: ClaudeModule? { manager.module(for: ClaudeModule.descriptor.id) as? ClaudeModule }
    private var unlock: UnlockModule? { manager.module(for: UnlockModule.descriptor.id) as? UnlockModule }

    private func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
