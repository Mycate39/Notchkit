import AppKit
import SwiftUI
import Observation

/// Module Étagère : fichiers déposés sur l'encoche, gardés à portée de main.
///
/// On glisse des fichiers sur l'encoche (zone « Étagère »), puis on les récupère plus tard en les
/// faisant glisser vers une autre app ou le Finder. Seule une référence (signet) est conservée :
/// les fichiers ne sont ni copiés ni déplacés.
@MainActor
@Observable
final class ShelfModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "shelf",
        name: "Étagère",
        summary: "Déposez des fichiers sur l'encoche pour les garder à portée de main ou les envoyer par AirDrop.",
        systemImage: "tray.full",
        category: .productivity,
        tier: .free,
        defaultEnabled: true,
        contextual: true
    )

    /// Nombre maximal de fichiers conservés (les plus anciens sont retirés au-delà).
    nonisolated static let maxItems = 40
    /// Temps laissé pour récupérer un fichier déposé, quand l'étagère se vide d'elle-même.
    nonisolated static let retention: TimeInterval = 5 * 60

    private(set) var items: [ShelfItem] = []
    /// Fichiers déjà récupérés (glissés hors de l'étagère) : ils restent dans le widget, mais
    /// l'étagère ne s'affiche plus comme activité en cours pour eux.
    private(set) var takenIDs: Set<UUID> = []
    /// Fichiers encore à récupérer.
    var pendingItems: [ShelfItem] { items.filter { !takenIDs.contains($0.id) } }
    let thumbnails = ShelfThumbnails()

    /// Affiche le nombre de fichiers dans l'encoche repliée.
    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }

    /// Chaque fichier reste `retention` (5 min) puis quitte l'étagère, qui s'affiche entre-temps comme
    /// une activité en cours (grande au centre, ou bulle à côté d'une autre activité).
    var autoClear: Bool {
        didSet {
            UserDefaults.standard.set(autoClear, forKey: Keys.autoClear)
            removeExpired()
        }
    }

    private enum Keys {
        static let items = "module.shelf.items"
        static let showInCompact = "module.shelf.showInCompact"
        static let autoClear = "module.shelf.autoClear"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? false
        autoClear = defaults.object(forKey: Keys.autoClear) as? Bool ?? true
        items = defaults.data(forKey: Keys.items)
            .flatMap { try? JSONDecoder().decode([ShelfItem].self, from: $0) } ?? []
    }

    func start() {
        removeExpired()
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
    }

    // MARK: Délai de récupération

    /// Fichiers dont le délai est écoulé (fonction pure, testée).
    nonisolated static func expired(_ items: [ShelfItem], at date: Date) -> [ShelfItem] {
        items.filter { $0.addedAt.addingTimeInterval(retention) <= date }
    }

    /// Retire les fichiers dont le délai est écoulé, puis attend le prochain.
    private func removeExpired() {
        expiryTask?.cancel()
        expiryTask = nil
        guard autoClear else { return }
        let gone = Set(Self.expired(items, at: Date()).map(\.id))
        if !gone.isEmpty { replaceItems(items.filter { !gone.contains($0.id) }) }
        guard let next = items.map({ $0.addedAt.addingTimeInterval(Self.retention) }).min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.removeExpired()
        }
    }

    // MARK: Actions

    /// Ajoute des fichiers. Un fichier déjà sur l'étagère, redéposé, repasse en tête avec 5 nouvelles
    /// minutes. Renvoie le nombre de fichiers ajoutés ou remis en tête.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let drop = Self.dropped(urls, onto: items, at: Date()) { $0.resolvedURL() }
        guard drop.count > 0 else { return 0 }
        replaceItems(drop.items)
        // Fichier déjà récupéré, redéposé : de nouveau à récupérer.
        takenIDs.subtract(drop.again)
        removeExpired()
        return drop.count
    }

    /// Étagère après un dépôt (fonction pure, testée) : les nouveaux fichiers en tête, puis ceux déjà
    /// là et redéposés (date remise à `date`), puis les autres ; au plus `maxItems`. `again` : fichiers
    /// redéposés ; `count` : nouveaux et redéposés.
    nonisolated static func dropped(_ urls: [URL], onto items: [ShelfItem], at date: Date,
                                    location: (ShelfItem) -> URL?) -> (items: [ShelfItem], again: Set<UUID>, count: Int) {
        var existing: [URL: UUID] = [:]
        for item in items { if let url = location(item)?.standardizedFileURL { existing[url] = item.id } }
        var seen = Set<URL>()
        var again = Set<UUID>()
        var new: [ShelfItem] = []
        for url in urls.map(\.standardizedFileURL) where seen.insert(url).inserted {
            if let id = existing[url] {
                again.insert(id)
            } else if let item = ShelfItem(url: url, date: date) {
                new.append(item)
            }
        }
        let moved = items.filter { again.contains($0.id) }.map { $0.added(at: date) }
        let rest = items.filter { !again.contains($0.id) }
        return (Array((new + moved + rest).prefix(maxItems)), again, new.count + moved.count)
    }

    /// Le fichier vient d'être glissé hors de l'étagère : il est récupéré au relâchement de la souris
    /// (marqué plus tôt, la bulle disparaîtrait sous le curseur pendant le glisser).
    func markTaken(_ item: ShelfItem) {
        Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, self.items.contains(where: { $0.id == item.id }) else { return }
            withAnimation(.snappy) { _ = self.takenIDs.insert(item.id) }
        }
    }

    func remove(_ item: ShelfItem) {
        replaceItems(items.filter { $0.id != item.id })
        removeExpired()
    }

    func clear() {
        replaceItems([])
        removeExpired()
    }

    /// Nouveau contenu de l'étagère. Les fichiers qui la quittent sont oubliés ; un texte déposé
    /// (fichier créé par Notchkit, que personne d'autre ne connaît) est effacé avec eux.
    private func replaceItems(_ newItems: [ShelfItem]) {
        let kept = Set(newItems.map(\.id))
        let leaving = items.filter { !kept.contains($0.id) }
        withAnimation(.snappy) {
            items = newItems
            takenIDs.formIntersection(kept)
        }
        ShelfTextClipping.discard(leaving.compactMap { $0.resolvedURL() })
        save()
    }

    func open(_ item: ShelfItem) {
        guard let url = item.resolvedURL() else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: ShelfItem) {
        guard let url = item.resolvedURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func airDrop(_ items: [ShelfItem]) {
        AirDrop.send(items.compactMap { $0.resolvedURL() })
    }

    /// Copie les fichiers dans le presse-papiers (à coller dans le Finder ou une autre app).
    func copy(_ items: [ShelfItem]) {
        let urls = items.compactMap { $0.resolvedURL() as NSURL? }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: Keys.items)
    }

    // MARK: Actions sur les fichiers

    /// Opération en cours (ZIP, conversion, copie) : l'en-tête affiche une roue.
    private(set) var isWorking = false

    func zip(_ items: [ShelfItem]) {
        perform(symbol: "doc.zipper") { await FileActions.zip(items.compactMap { $0.resolvedURL() }).map { [$0] } ?? [] }
    }

    /// Conversion par le moteur du convertisseur ; le fichier créé rejoint l'étagère.
    func convert(_ item: ShelfItem, to format: ConversionFormat) {
        guard let url = item.resolvedURL() else { return }
        perform(symbol: ConversionKind.of(url)?.symbol ?? "arrow.triangle.2.circlepath") {
            (try? await FileConverter.convert(url, to: format)).map { [$0] } ?? []
        }
    }

    func copyToICloud(_ items: [ShelfItem]) {
        perform(symbol: "icloud.and.arrow.up", addToShelf: false) {
            await FileActions.copyToICloud(items.compactMap { $0.resolvedURL() })
        }
    }

    var isICloudAvailable: Bool { FileActions.iCloudFolder != nil }

    /// Lance une action, ajoute ses fichiers à l'étagère et confirme dans l'encoche.
    private func perform(symbol: String, addToShelf: Bool = true, _ action: @escaping @MainActor () async -> [URL]) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let results = await action()
            isWorking = false
            if addToShelf { add(results) }
            context.presentAlert(ShelfAlerts.actionFinished(symbol: symbol, succeeded: !results.isEmpty))
        }
    }

    /// Des fichiers sont posés sur l'étagère : elle s'affiche même si son widget est masqué.
    var hasContextualContent: Bool { !items.isEmpty }

    // MARK: Affichage

    var compactPriority: ModulePriority {
        guard !pendingItems.isEmpty else { return .none }
        // Fichiers à récupérer dans les 5 minutes : activité en cours.
        if autoClear { return .normal }
        return showInCompact ? .low : .none
    }

    var expandedWidthWeight: CGFloat { 2 }


    func compactLeading() -> AnyView? {
        guard !pendingItems.isEmpty else { return nil }
        return AnyView(Image(systemName: "tray.full.fill").foregroundStyle(.white.opacity(0.85)))
    }

    /// Bulle survolée : les derniers fichiers déposés, à faire glisser où l'on veut.
    func bubbleControls() -> AnyView? {
        items.isEmpty ? nil : AnyView(ShelfBubbleFiles(module: self))
    }

    var bubbleControlsWidth: CGFloat {
        ShelfBubbleFiles.width(count: items.count)
    }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: items.isEmpty ? "tray" : "tray.full.fill", value: "\(items.count)",
                           caption: String(localized: "Étagère")))
    }

    func expandedView() -> AnyView {
        AnyView(ShelfExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(ShelfSettingsView(module: self))
    }
}

/// Alerte affichée après un dépôt sur l'étagère.
enum ShelfAlerts {
    @MainActor
    static func actionFinished(symbol: String, succeeded: Bool) -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: symbol).foregroundStyle(succeeded ? .green : .red)),
            trailing: AnyView(Image(systemName: succeeded ? "checkmark" : "xmark").foregroundStyle(succeeded ? .green : .red)),
            duration: .seconds(2)
        )
    }

    @MainActor
    static func added(_ count: Int) -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.green)),
            trailing: AnyView(Text("+\(count)").monospacedDigit().foregroundStyle(.green)),
            duration: .seconds(2)
        )
    }
}

#if DEBUG
extension ShelfModule {
    /// Fichiers fictifs pour les images de démonstration (non enregistrés).
    func debugSetItems(_ items: [ShelfItem]) {
        self.items = items
    }
}
#endif
