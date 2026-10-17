import AppKit
import SwiftUI
import Observation

/// Téléchargement en cours ou terminé.
struct VideoDownload: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case running
        case finished(path: String?)
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let link: String
    let format: YTDLP.Format
    /// Résolution choisie, ou `nil` (meilleure disponible).
    var height: Int?
    var title: String
    var progress: Double = 0
    var detail = ""
    var state: State = .running
    /// Codec vidéo retenu par yt-dlp et durée, pour décider de la conversion et la suivre.
    var videoCodec: String?
    var duration: Double?
    var isConverting = false

    var isRunning: Bool { state == .running }
    /// Une conversion HEVC suivra le téléchargement.
    var willConvert: Bool { YTDLP.needsConversion(videoCodec: videoCodec) }

    /// Avancement global : le téléchargement compte pour 60 % quand une conversion suit.
    static func overallProgress(download: Double, conversion: Double?, willConvert: Bool) -> Double {
        guard willConvert else { return download }
        return conversion.map { 0.6 + 0.4 * $0 } ?? 0.6 * download
    }
}

/// Lien collé en attente du choix de la résolution.
struct ResolutionChoice: Equatable, Sendable {
    let link: String
    /// Résolutions proposées par la vidéo ; `nil` pendant la recherche.
    var heights: [Int]?
}

/// Module Vidéos : télécharge une vidéo (ou son audio) à partir d'un lien, avec yt-dlp.
///
/// ⚠️ Les conditions d'utilisation de YouTube interdisent de télécharger des vidéos sans
/// autorisation : à réserver à vos propres vidéos, aux contenus sous licence libre ou
/// téléchargés avec l'accord de leurs auteurs.
@MainActor
@Observable
final class VideoDownloadModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "videodownload",
        name: "Vidéos",
        summary: "Téléchargez une vidéo ou son audio à partir d'un lien (avec yt-dlp).",
        systemImage: "arrow.down.to.line.circle",
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    private(set) var downloads: [VideoDownload] = []
    private(set) var resolutionChoice: ResolutionChoice?
    private(set) var isToolInstalled = YTDLP.executable != nil
    private(set) var hasFFmpeg = YTDLP.ffmpeg != nil
    private(set) var installLog: String?
    private(set) var isInstalling = false

    var format: YTDLP.Format {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: Keys.format) }
    }
    /// Dossier de destination.
    var directory: URL {
        didSet { UserDefaults.standard.set(directory.path, forKey: Keys.directory) }
    }

    private enum Keys {
        static let format = "module.videodownload.format"
        static let directory = "module.videodownload.directory"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var processes: [UUID: Process] = [:]
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    /// Avancement du téléchargement seul (avant conversion), par téléchargement.
    @ObservationIgnored private var downloadProgress: [UUID: Double] = [:]

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Keys.format).flatMap(YTDLP.Format.init(rawValue:)) ?? .bestVideo
        // Anciens choix 1080p / 720p : la résolution se choisit maintenant d'après la vidéo.
        format = YTDLP.Format.menuCases.contains(saved) ? saved : .bestVideo
        directory = defaults.string(forKey: Keys.directory).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func stop() {
        probeTask?.cancel()
        resolutionChoice = nil
        processes.values.forEach { $0.terminate() }
        processes.removeAll()
    }

    func refreshToolStatus() {
        isToolInstalled = YTDLP.executable != nil
        hasFFmpeg = YTDLP.ffmpeg != nil
    }

    // MARK: Téléchargement

    /// Lien collé : en vidéo (avec ffmpeg), on cherche d'abord les résolutions proposées pour
    /// laisser choisir ; sinon le téléchargement démarre tout de suite.
    func prepareDownload(_ link: String) {
        // ffmpeg a pu être installé depuis le lancement : on vérifie à chaque téléchargement.
        refreshToolStatus()
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard YTDLP.isValidLink(trimmed), let tool = YTDLP.executable else { return }
        guard !format.isAudio, hasFFmpeg else {
            download(trimmed, height: nil)
            return
        }
        resolutionChoice = ResolutionChoice(link: trimmed, heights: nil)
        probeTask?.cancel()
        let environment = Self.toolEnvironment
        probeTask = Task { [weak self] in
            let heights = await Self.probeHeights(tool: tool, url: trimmed, environment: environment)
            guard let self, !Task.isCancelled, self.resolutionChoice?.link == trimmed else { return }
            if heights.isEmpty {
                // Résolutions illisibles : on télécharge la meilleure qualité, comme avant.
                self.resolutionChoice = nil
                self.download(trimmed, height: nil)
            } else {
                withAnimation(.snappy) { self.resolutionChoice?.heights = heights }
            }
        }
    }

    /// Résolution choisie dans la liste.
    func chooseResolution(_ height: Int) {
        guard let choice = resolutionChoice else { return }
        resolutionChoice = nil
        download(choice.link, height: height)
    }

    func cancelResolutionChoice() {
        probeTask?.cancel()
        withAnimation(.snappy) { resolutionChoice = nil }
    }

    /// Lance `yt-dlp -J` hors du thread principal et lit les hauteurs proposées.
    private nonisolated static func probeHeights(tool: URL, url: String, environment: [String: String]) async -> [Int] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = tool
                process.arguments = YTDLP.probeArguments(url: url)
                process.environment = environment
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: []) }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? YTDLP.availableHeights(json: data) : [])
            }
        }
    }

    /// Environnement des outils : leurs dossiers d'abord (yt-dlp y trouve ffmpeg et deno).
    private static var toolEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (YTDLP.searchPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
        return environment
    }

    func download(_ link: String, height: Int?) {
        refreshToolStatus()
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard YTDLP.isValidLink(trimmed), let tool = YTDLP.executable else { return }
        let format = (self.format.requiresFFmpeg && !hasFFmpeg) ? .audioM4A : self.format

        var item = VideoDownload(link: trimmed, format: format, height: format.isAudio ? nil : height,
                                 title: URL(string: trimmed)?.host() ?? trimmed)
        item.detail = String(localized: "Préparation…")
        withAnimation(.snappy) { downloads.insert(item, at: 0) }

        let process = Process()
        process.executableURL = tool
        process.arguments = YTDLP.arguments(url: trimmed, format: format, directory: directory,
                                            hasFFmpeg: hasFFmpeg, ffmpegLocation: YTDLP.ffmpeg, height: item.height)
        process.environment = Self.toolEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let id = item.id
        let buffer = OutputLineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for line in buffer.append(data) {
                        if let parsed = YTDLP.parse(line) { self?.apply(parsed, to: id) }
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.processEnded(id, status: status, reason: reason) }
            }
        }

        do {
            try process.run()
            processes[id] = process
        } catch {
            update(id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    func cancel(_ id: UUID) {
        update(id) { $0.state = .cancelled }
        processes[id]?.terminate()
    }

    func remove(_ id: UUID) {
        cancel(id)
        withAnimation(.snappy) { downloads.removeAll { $0.id == id } }
    }

    func reveal(_ download: VideoDownload) {
        if case let .finished(path?) = download.state {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    /// Choix du dossier de destination.
    func chooseDirectory() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        panel.prompt = String(localized: "Choisir")
        panel.message = String(localized: "Dossier où enregistrer les vidéos téléchargées")
        if panel.runModal() == .OK, let url = panel.url { directory = url }
    }

    private func apply(_ line: YTDLP.OutputLine, to id: UUID) {
        let ffmpegAvailable = hasFFmpeg
        let downloaded = max(downloadProgress[id] ?? 0, { if case let .progress(p, _) = line { p } else { 0 } }())
        downloadProgress[id] = downloaded
        update(id) { item in
            switch line {
            case let .title(title): item.title = title
            case let .videoCodec(codec): item.videoCodec = codec
            case let .duration(seconds): item.duration = seconds
            case let .progress(_, detail):
                item.progress = VideoDownload.overallProgress(download: downloaded, conversion: nil,
                                                              willConvert: item.willConvert)
                item.detail = detail
            case let .file(path): item.state = .finished(path: path)
            case let .error(message): item.detail = YTDLP.displayError(message, hasFFmpeg: ffmpegAvailable)
            }
        }
    }

    private func processEnded(_ id: UUID, status: Int32, reason: Process.TerminationReason) {
        processes[id] = nil
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        if item.state == .cancelled { return }
        // AV1 ou VP9 : conversion HEVC avant d'annoncer la fin.
        if status == 0, !item.isConverting, item.willConvert, case let .finished(path?) = item.state,
           let ffmpeg = YTDLP.ffmpeg {
            convert(id, file: URL(fileURLWithPath: path), ffmpeg: ffmpeg)
            return
        }
        downloadProgress[id] = nil
        if status == 0 {
            update(id) { item in
                if case .running = item.state { item.state = .finished(path: nil) }
                item.progress = 1
                item.detail = ""
            }
            context.presentAlert(NotchAlert(
                leading: AnyView(Image(systemName: "arrow.down.to.line.circle.fill").foregroundStyle(.red)),
                trailing: AnyView(Image(systemName: "checkmark").foregroundStyle(.green)),
                duration: .seconds(2.5)
            ))
        } else {
            update(id) { item in
                let message = item.detail.isEmpty ? String(localized: "Échec du téléchargement") : item.detail
                item.state = .failed(message)
            }
        }
    }

    // MARK: Conversion

    /// Convertit le fichier en HEVC (encodeur matériel), puis remplace l'original.
    private func convert(_ id: UUID, file: URL, ffmpeg: URL) {
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        let output = file.deletingPathExtension().appendingPathExtension("hevc-partial.mp4")
        let duration = item.duration ?? 0
        update(id) { item in
            item.state = .running
            item.isConverting = true
            item.progress = VideoDownload.overallProgress(download: 1, conversion: 0, willConvert: true)
            item.detail = String(localized: "Conversion en HEVC…")
        }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = YTDLP.conversionArguments(input: file, output: output, height: item.height)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let buffer = OutputLineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for line in buffer.append(data) {
                        guard let fraction = YTDLP.conversionProgress(line, duration: duration) else { continue }
                        self?.update(id) { item in
                            item.progress = VideoDownload.overallProgress(download: 1, conversion: fraction, willConvert: true)
                            item.detail = String(localized: "Conversion en HEVC…")
                        }
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.conversionEnded(id, status: status, original: file, output: output) }
            }
        }
        do {
            try process.run()
            processes[id] = process
        } catch {
            conversionEnded(id, status: -1, original: file, output: output)
        }
    }

    private func conversionEnded(_ id: UUID, status: Int32, original: URL, output: URL) {
        processes[id] = nil
        downloadProgress[id] = nil
        let manager = FileManager.default
        let cancelled = downloads.first(where: { $0.id == id })?.state == .cancelled
        guard status == 0, !cancelled, (try? manager.replaceItemAt(original, withItemAt: output)) != nil else {
            // Annulée ou en échec : on garde la vidéo d'origine (lisible avec VLC ou IINA).
            try? manager.removeItem(at: output)
            if cancelled { return }
            update(id) { item in
                item.isConverting = false
                item.state = .finished(path: original.path)
                item.progress = 1
                item.detail = String(localized: "Conversion impossible : vidéo gardée dans son format d'origine.")
            }
            return
        }
        update(id) { item in
            item.isConverting = false
            item.state = .finished(path: original.path)
            item.progress = 1
            item.detail = ""
        }
        context.presentAlert(NotchAlert(
            leading: AnyView(Image(systemName: "arrow.down.to.line.circle.fill").foregroundStyle(.red)),
            trailing: AnyView(Image(systemName: "checkmark").foregroundStyle(.green)),
            duration: .seconds(2.5)
        ))
    }

    private func update(_ id: UUID, _ change: (inout VideoDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        change(&downloads[index])
    }

    // MARK: Installation de l'outil

    /// Installe yt-dlp en téléchargeant le programme officiel (empreinte vérifiée).
    func installTool() {
        guard !isInstalling else { return }
        isInstalling = true
        installLog = String(localized: "Téléchargement de yt-dlp… (environ 35 Mo)")
        Task { [weak self] in
            do {
                try await YTDLPInstaller.install()
                self?.installLog = String(localized: "yt-dlp est installé.")
            } catch {
                self?.installLog = String(localized: "L'installation a échoué : \(error.localizedDescription)")
            }
            self?.isInstalling = false
            self?.refreshToolStatus()
        }
    }

    // MARK: Affichage

    private var activeDownload: VideoDownload? { downloads.first(where: \.isRunning) }

    var compactPriority: ModulePriority { activeDownload != nil ? .normal : .none }

    var expandedWidthWeight: CGFloat { 2 }

    /// Juste la place de « 100 % ».
    var compactSideWidth: CGFloat { 52 }

    func compactLeading() -> AnyView? {
        guard activeDownload != nil else { return nil }
        return AnyView(Image(systemName: "arrow.down.to.line.circle.fill").foregroundStyle(.red))
    }

    func compactTrailing() -> AnyView? {
        guard let download = activeDownload else { return nil }
        return AnyView(Text(download.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit())
    }

    func miniView() -> AnyView {
        if let download = activeDownload {
            return AnyView(MiniWidget(symbol: "arrow.down.to.line.circle.fill",
                                      value: download.progress.formatted(.percent.precision(.fractionLength(0))),
                                      caption: download.title, tint: .red))
        }
        return AnyView(MiniWidget(symbol: "arrow.down.to.line.circle", value: nil, caption: String(localized: "Vidéos")))
    }

    func expandedView() -> AnyView {
        AnyView(VideoDownloadExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(VideoDownloadSettingsView(module: self))
    }

    func holdExpanded(_ hold: Bool) {
        context.holdExpanded(hold)
    }

    func openSettings() {
        context.openSettings()
    }
}

/// Tampon de la sortie de yt-dlp, découpée en lignes. Isolé sur le thread principal
/// pour pouvoir être capturé par le gestionnaire de lecture du pipe sans course de données.
@MainActor
private final class OutputLineBuffer {
    private var data = Data()

    /// Ajoute un morceau de sortie et renvoie les lignes complètes qu'il termine.
    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let newline = data.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            lines.append(String(decoding: data[data.startIndex..<newline], as: UTF8.self))
            data.removeSubrange(data.startIndex...newline)
        }
        return lines
    }
}
