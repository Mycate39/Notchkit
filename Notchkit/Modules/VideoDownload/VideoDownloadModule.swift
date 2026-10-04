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
    var title: String
    var progress: Double = 0
    var detail = ""
    var state: State = .running

    var isRunning: Bool { state == .running }
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

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        format = defaults.string(forKey: Keys.format).flatMap(YTDLP.Format.init(rawValue:)) ?? .bestVideo
        directory = defaults.string(forKey: Keys.directory).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func stop() {
        processes.values.forEach { $0.terminate() }
        processes.removeAll()
    }

    func refreshToolStatus() {
        isToolInstalled = YTDLP.executable != nil
        hasFFmpeg = YTDLP.ffmpeg != nil
    }

    // MARK: Téléchargement

    func download(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard YTDLP.isValidLink(trimmed), let tool = YTDLP.executable else { return }
        let format = (self.format.requiresFFmpeg && !hasFFmpeg) ? .audioM4A : self.format

        var item = VideoDownload(link: trimmed, format: format, title: URL(string: trimmed)?.host() ?? trimmed)
        item.detail = String(localized: "Préparation…")
        withAnimation(.snappy) { downloads.insert(item, at: 0) }

        let process = Process()
        process.executableURL = tool
        process.arguments = YTDLP.arguments(url: trimmed, format: format, directory: directory,
                                            hasFFmpeg: hasFFmpeg, ffmpegLocation: YTDLP.ffmpeg)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (YTDLP.searchPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let id = item.id
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    buffer.append(data)
                    while let newline = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                        let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                        buffer.removeSubrange(buffer.startIndex...newline)
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
        processes[id]?.terminate()
        update(id) { $0.state = .cancelled }
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
        update(id) { item in
            switch line {
            case let .title(title): item.title = title
            case let .progress(percent, detail):
                item.progress = max(item.progress, percent)
                item.detail = detail
            case let .file(path): item.state = .finished(path: path)
            case let .error(message): item.detail = message
            }
        }
    }

    private func processEnded(_ id: UUID, status: Int32, reason: Process.TerminationReason) {
        processes[id] = nil
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        if item.state == .cancelled { return }
        if status == 0 {
            update(id) { item in
                if case .running = item.state { item.state = .finished(path: nil) }
                item.progress = 1
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

    private func update(_ id: UUID, _ change: (inout VideoDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        change(&downloads[index])
    }

    // MARK: Installation de l'outil

    /// Installe yt-dlp (et ffmpeg si demandé) avec Homebrew.
    func installTools(includeFFmpeg: Bool) {
        guard let brew = YTDLP.brew, !isInstalling else { return }
        isInstalling = true
        installLog = String(localized: "Installation en cours… (cela peut prendre quelques minutes)")
        let process = Process()
        process.executableURL = brew
        process.arguments = ["install", "yt-dlp"] + (includeFFmpeg ? ["ffmpeg"] : [])
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.isInstalling = false
                    self?.refreshToolStatus()
                    self?.installLog = status == 0
                        ? String(localized: "Installation terminée.")
                        : String(localized: "L'installation a échoué. Essayez dans le Terminal : brew install yt-dlp")
                }
            }
        }
        do { try process.run() } catch {
            isInstalling = false
            installLog = error.localizedDescription
        }
    }

    // MARK: Affichage

    private var activeDownload: VideoDownload? { downloads.first(where: \.isRunning) }

    var compactPriority: ModulePriority { activeDownload != nil ? .normal : .none }

    var expandedWidthWeight: CGFloat { 2 }

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
