import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers
import os

/// Module Captures d'écran : les captures et enregistrements d'écran faits depuis l'ouverture
/// de la session, à glisser vers une autre app, ouvrir, copier ou envoyer par AirDrop.
///
/// Recherche Spotlight en direct (API publique `NSMetadataQuery`) sur l'étiquette que macOS pose
/// sur chaque capture (`kMDItemIsScreenCapture`) : peu importe le dossier où elles sont enregistrées.
@MainActor
@Observable
final class ScreenshotsModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "screenshots",
        name: "Captures d'écran",
        summary: "Les captures et enregistrements d'écran de votre session, à glisser où vous voulez.",
        systemImage: "camera.viewfinder",
        category: .productivity,
        tier: .free,
        // Masqué par défaut : il apparaît de lui-même dès qu'il y a une capture dans la session.
        defaultEnabled: false,
        contextual: true
    )

    private(set) var items: [Screenshot] = []
    let thumbnails = ShelfThumbnails()

    /// Petite alerte dans l'encoche à chaque nouvelle capture.
    var alertOnCapture: Bool {
        didSet { UserDefaults.standard.set(alertOnCapture, forKey: Keys.alertOnCapture) }
    }

    private enum Keys {
        static let alertOnCapture = "module.screenshots.alertOnCapture"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var hasGathered = false
    @ObservationIgnored private let sessionStart = ScreenshotSession.start(
        boot: ScreenshotSession.bootDate, login: ScreenshotSession.loginDate
    )

    init(context: ModuleContext) {
        self.context = context
        alertOnCapture = UserDefaults.standard.object(forKey: Keys.alertOnCapture) as? Bool ?? true
    }

    // MARK: Cycle de vie

    func start() {
        // Tests automatisés : pas de recherche (les aperçus pourraient demander l'accès au Bureau).
        guard query == nil, !AutomatedRun.isActive else { return }
        let query = NSMetadataQuery()
        let recording = ScreenshotSession.recordingPrefixes
            .map { "kMDItemFSName BEGINSWITH \"\($0)\"" }
            .joined(separator: " OR ")
        query.predicate = NSPredicate(
            format: "(kMDItemIsScreenCapture == 1 OR (kMDItemContentTypeTree == 'public.movie' AND (\(recording)))) AND kMDItemFSCreationDate >= %@",
            sessionStart as NSDate
        )
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]

        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        self.query = query
        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        hasGathered = false
    }

    private func refresh() {
        guard let query else { return }
        query.disableUpdates()
        let found: [Screenshot] = (0..<query.resultCount).compactMap { index in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  FileManager.default.fileExists(atPath: path)
            else { return nil }
            let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
            let type = (item.value(forAttribute: NSMetadataItemContentTypeKey) as? String).flatMap(UTType.init)
            return Screenshot(url: URL(fileURLWithPath: path), date: date, isVideo: type?.conforms(to: .movie) ?? false)
        }
        query.enableUpdates()

        let updated = ScreenshotSession.sessionItems(found, since: sessionStart)
        Logger(subsystem: "com.andeolchenaux.notchkit", category: "screenshots")
            .notice("captures de la session : \(updated.count) (depuis \(self.sessionStart, privacy: .public))")
        let previous = Set(items.map(\.url))
        let added = updated.filter { !previous.contains($0.url) }
        withAnimation(.snappy) { items = updated }

        // Alerte seulement pour les captures faites pendant que Notchkit tourne.
        if hasGathered, alertOnCapture, let newest = added.first {
            context.presentAlert(ScreenshotAlerts.captured(newest, module: self))
        }
        hasGathered = true
    }

    // MARK: Actions

    func open(_ item: Screenshot) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ items: [Screenshot]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func airDrop(_ items: [Screenshot]) {
        AirDrop.send(items.map(\.url))
    }

    /// Copie le fichier (à coller dans le Finder, un message, un document…).
    func copy(_ item: Screenshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }

    /// Place la capture dans la corbeille (récupérable).
    func moveToTrash(_ item: Screenshot) {
        NSWorkspace.shared.recycle([item.url]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    withAnimation(.snappy) { self?.items.removeAll { $0.url == item.url } }
                }
            }
        }
    }

    // MARK: Affichage

    /// Au moins une capture dans la session : le widget s'affiche même s'il est masqué.
    var hasContextualContent: Bool { !items.isEmpty }

    var compactPriority: ModulePriority { .none }

    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "camera.viewfinder", value: "\(items.count)",
                           caption: String(localized: "Captures")))
    }

    func expandedView() -> AnyView {
        AnyView(ScreenshotsExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(ScreenshotsSettingsView(module: self))
    }
}

enum ScreenshotAlerts {
    /// Nouvelle capture : son aperçu à gauche, « Capture » à droite.
    @MainActor
    static func captured(_ item: Screenshot, module: ScreenshotsModule) -> NotchAlert {
        NotchAlert(
            leading: AnyView(ScreenshotThumbnail(item: item, module: module, size: CGSize(width: 30, height: 20))),
            trailing: AnyView(
                Text(item.isVideo ? "Enregistrement" : "Capture")
                    .foregroundStyle(.white.opacity(0.85))
                    .minimumScaleFactor(0.7)
            ),
            duration: .seconds(2.5)
        )
    }
}
