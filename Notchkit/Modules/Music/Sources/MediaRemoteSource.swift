import Foundation

/// Reconstitue l'état courant à partir du flux JSON de `mediaremote-adapter stream`.
/// Chaque ligne contient soit l'état complet (`diff: false`), soit seulement les clés modifiées
/// (`diff: true`, une valeur `null` signifiant que la clé a disparu).
struct MediaRemoteStream {
    private(set) var state: [String: Any] = [:]

    /// Applique une ligne du flux et renvoie le nouvel état, ou `nil` si la ligne est invalide.
    mutating func apply(line: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return nil }

        if object["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload
        }
        return state
    }
}

/// Source « Toutes les apps » : lit le morceau en cours de n'importe quel lecteur via MediaRemote.
///
/// ⚠️ API PRIVÉE. On lance `/usr/bin/perl` avec le script de mediaremote-adapter
/// (code tiers BSD, voir ThirdParty/MediaRemoteAdapter/PROVENANCE.md). Le processus reste
/// en attente et n'écrit qu'à chaque changement : il ne consomme rien entre deux morceaux.
/// Si Apple bloque ce mécanisme, le flux reste vide et le module se replie sur Music/Spotify.
@MainActor
final class MediaRemoteSource {
    var onUpdate: (@MainActor (NowPlayingInfo?) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var stream = MediaRemoteStream()
    private var isRunning = false
    private var restartAttempts = 0
    private var restartTask: Task<Void, Never>?

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let maxRestartAttempts = 5

    /// Script et framework intégrés à l'app, ou `nil` s'ils manquent.
    private static var resources: (script: String, framework: String)? {
        guard let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let framework = Bundle.main.privateFrameworksURL?
                .appendingPathComponent("MediaRemoteAdapter.framework").path,
              FileManager.default.fileExists(atPath: framework)
        else { return nil }
        return (script, framework)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        restartAttempts = 0
        launch()
    }

    func stop() {
        isRunning = false
        restartTask?.cancel()
        restartTask = nil
        terminateProcess()
        reset()
    }

    /// Envoie une commande au lecteur actif (processus court, sans attendre la fin).
    func send(_ command: PlaybackCommand) {
        guard let resources = Self.resources else { return }
        // Identifiants des commandes MediaRemote (voir la documentation de mediaremote-adapter).
        let id = switch command {
        case .togglePlayPause: "2"
        case .nextTrack: "4"
        case .previousTrack: "5"
        }
        let task = Process()
        task.executableURL = Self.perl
        task.arguments = [resources.script, resources.framework, "send", id]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    // MARK: - Processus

    private func launch() {
        guard isRunning, process == nil, let resources = Self.resources else { return }

        let task = Process()
        task.executableURL = Self.perl
        task.arguments = [resources.script, resources.framework, "stream", "--micros", "--debounce=80"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // Les données arrivent sur un thread d'arrière-plan : on les renvoie dans l'ordre
        // sur la file principale (une pochette peut être découpée en plusieurs morceaux).
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil // fin du flux
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(data) }
            }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.processDidEnd() }
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let payload = stream.apply(line: Data(line)) else { continue }
            restartAttempts = 0
            onUpdate?(NowPlayingInfo(mediaRemotePayload: payload))
        }
    }

    /// Le processus s'est arrêté : on le relance avec un délai croissant (2, 4, 8… s).
    private func processDidEnd() {
        process = nil
        reset()
        guard isRunning, restartAttempts < Self.maxRestartAttempts else { return }
        restartAttempts += 1
        let delay = Double(1 << restartAttempts)
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func terminateProcess() {
        guard let process else { return }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
    }

    private func reset() {
        buffer = Data()
        stream = MediaRemoteStream()
        onUpdate?(nil)
    }
}
