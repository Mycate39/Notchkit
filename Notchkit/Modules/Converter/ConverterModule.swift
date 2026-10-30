import AppKit
import Observation
import SwiftUI

/// Module Convertisseur : on dépose des fichiers sur l'encoche (zone « Convertir ») ou dans le widget
/// ouvert, puis on choisit le format de sortie. Images, audio, vidéos, documents et PDF, tout sur le Mac.
/// Widget temporaire (contextuel) : même masqué, il apparaît en dernière page tant qu'il a des fichiers.
@MainActor
@Observable
final class ConverterModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "converter",
        name: "Convertisseur",
        summary: "Convertissez images, sons, vidéos et documents : déposez-les sur l'encoche puis choisissez le format.",
        systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard",
        category: .productivity,
        tier: .free,
        defaultEnabled: false,
        contextual: true
    )

    /// Nombre de fichiers convertis en une fois au plus.
    nonisolated static let maxFiles = 20

    private(set) var files: [URL] = []
    private(set) var results: [URL] = []
    private(set) var isConverting = false
    private(set) var completed = 0
    /// Avancement du fichier en cours (0 à 1), pour les conversions longues (vidéo, GIF, PDF).
    private(set) var currentProgress: Double = 0
    /// Avancement de toute la conversion (0 à 1).
    var progress: Double { Self.progress(completed: completed, current: currentProgress, total: files.count) }
    private(set) var failures = 0
    private(set) var lastError: String?
    /// Un fichier est glissé au-dessus du widget ouvert : il y sera déposé directement.
    var isDropTargeted = false

    var hasContextualContent: Bool { !files.isEmpty || isConverting || !results.isEmpty }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var task: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
    }

    func stop() {
        task?.cancel()
    }

    /// Formats proposés pour les fichiers en attente.
    var formats: [ConversionFormat] { FileConverter.commonFormats(for: files) }

    /// Famille des fichiers (celle du premier, les autres partagent au moins un format).
    var kind: ConversionKind? { files.first.flatMap(ConversionKind.of) }

    /// Avancement global (fonction pure, testée).
    nonisolated static func progress(completed: Int, current: Double, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(completed) + min(max(current, 0), 1)) / Double(total))
    }

    /// Ajoute des fichiers à ceux en attente s'ils sont de la même famille, sinon les remplace ;
    /// renvoie le nombre de fichiers pris en charge.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        guard !isConverting else { return 0 }
        let merged = Self.merged(pending: files, dropped: urls)
        guard !merged.isEmpty else {
            lastError = String(localized: "Aucun de ces fichiers ne peut être converti.")
            return 0
        }
        files = merged
        results = []
        failures = 0
        completed = 0
        lastError = nil
        // Fichiers déposés désormais en attente (un fichier déjà là compte aussi).
        return urls.filter(merged.contains).count
    }

    /// Fichiers en attente après un dépôt : les nouveaux s'ajoutent (sans doublon) s'ils sont de la même
    /// famille que ceux déjà là, sinon ils les remplacent (fonction pure, testée).
    nonisolated static func merged(pending: [URL], dropped: [URL]) -> [URL] {
        let dropped = supported(dropped)
        guard !pending.isEmpty, !dropped.isEmpty else { return dropped }
        let new = dropped.filter { !pending.contains($0) }
        guard !new.isEmpty else { return pending }
        // Une autre famille (des images après un document) : les fichiers déposés remplacent ceux en
        // attente, même si un format reste commun (PDF).
        let kind = ConversionKind.of(pending[0])
        guard new.allSatisfy({ ConversionKind.of($0) == kind }) else { return dropped }
        return Array((pending + new).prefix(maxFiles))
    }

    /// Fichiers convertibles, dans la limite de `maxFiles`, en gardant ceux qui ont un format commun
    /// avec le premier (fonction pure, testée).
    nonisolated static func supported(_ urls: [URL]) -> [URL] {
        var kept: [URL] = []
        for url in urls where !FileConverter.formats(for: url).isEmpty {
            if kept.isEmpty || !FileConverter.commonFormats(for: kept + [url]).isEmpty { kept.append(url) }
            if kept.count == maxFiles { break }
        }
        return kept
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choisissez les fichiers à convertir")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
        context.showModule()
    }

    func convert(to format: ConversionFormat) {
        guard !isConverting, !files.isEmpty else { return }
        isConverting = true
        completed = 0
        currentProgress = 0
        failures = 0
        results = []
        lastError = nil
        let files = files
        task = Task { [weak self] in
            for url in files {
                guard let self, !Task.isCancelled else { return }
                if FileConverter.isAlready(url, in: format) {
                    self.completed += 1
                    continue
                }
                do {
                    let output = try await FileConverter.convert(url, to: format) { [weak self] value in
                        self?.currentProgress = value
                    }
                    self.results.append(output)
                } catch {
                    self.failures += 1
                    self.lastError = error.localizedDescription
                }
                self.currentProgress = 0
                self.completed += 1
            }
            self?.finish()
        }
    }

    private func finish() {
        isConverting = false
        let succeeded = !results.isEmpty
        Haptics.play(.tap)
        context.presentAlert(ConverterAlerts.finished(count: results.count, succeeded: succeeded))
        if succeeded { files = [] }
    }

    #if DEBUG
    /// Résultat imposé pour les captures de développement.
    func debugSetResults(_ urls: [URL]) {
        files = []
        results = urls
    }
    #endif

    func revealResults() {
        guard !results.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(results)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func clear() {
        guard !isConverting else { return }
        files = []
        results = []
        failures = 0
        lastError = nil
    }

    // MARK: Encoche repliée : progression pendant la conversion

    var compactPriority: ModulePriority { isConverting ? .normal : .none }

    func compactLeading() -> AnyView? {
        guard isConverting else { return nil }
        return AnyView(Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tint)
            .symbolEffect(.pulse, isActive: true))
    }

    func compactTrailing() -> AnyView? {
        guard isConverting else { return nil }
        return AnyView(Text(verbatim: "\(completed)/\(files.count)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white))
    }

    /// Assez large pour son titre et ses boutons de formats.
    var expandedWidthWeight: CGFloat { 1.5 }

    // MARK: Vues

    func expandedView() -> AnyView {
        AnyView(ConverterExpandedView(module: self))
    }

    func miniView() -> AnyView {
        AnyView(ConverterMiniView(module: self))
    }
}

enum ConverterAlerts {
    /// Fichiers déposés sur « Convertir » qu'aucun format ne prend en charge.
    @MainActor
    static func unsupported() -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.red)),
            trailing: AnyView(Image(systemName: "xmark").foregroundStyle(.red)),
            duration: .seconds(2)
        )
    }

    @MainActor
    static func finished(count: Int, succeeded: Bool) -> NotchAlert {
        var alert = NotchAlert(
            leading: AnyView(Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(succeeded ? .green : .red)),
            trailing: AnyView(Group {
                if succeeded {
                    Text(verbatim: "\(count)").monospacedDigit().foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark").foregroundStyle(.red)
                }
            }),
            duration: .seconds(2)
        )
        alert.openModuleID = ConverterModule.descriptor.id
        return alert
    }
}
