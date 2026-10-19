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

    /// Remplace les fichiers en attente ; renvoie le nombre de fichiers pris en charge.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        guard !isConverting else { return 0 }
        let supported = Self.supported(urls)
        guard !supported.isEmpty else {
            lastError = String(localized: "Aucun de ces fichiers ne peut être converti.")
            return 0
        }
        files = supported
        results = []
        failures = 0
        completed = 0
        lastError = nil
        return supported.count
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
                    let output = try await FileConverter.convert(url, to: format)
                    self.results.append(output)
                } catch {
                    self.failures += 1
                    self.lastError = error.localizedDescription
                }
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

    // MARK: Vues

    func expandedView() -> AnyView {
        AnyView(ConverterExpandedView(module: self))
    }

    func miniView() -> AnyView {
        AnyView(ConverterMiniView(module: self))
    }
}

enum ConverterAlerts {
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
