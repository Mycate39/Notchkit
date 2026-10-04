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
        defaultEnabled: true
    )

    /// Nombre maximal de fichiers conservés (les plus anciens sont retirés au-delà).
    static let maxItems = 40

    private(set) var items: [ShelfItem] = []
    let thumbnails = ShelfThumbnails()

    /// Affiche le nombre de fichiers dans l'encoche repliée.
    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }

    private enum Keys {
        static let items = "module.shelf.items"
        static let showInCompact = "module.shelf.showInCompact"
    }

    @ObservationIgnored private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? false
        items = defaults.data(forKey: Keys.items)
            .flatMap { try? JSONDecoder().decode([ShelfItem].self, from: $0) } ?? []
    }

    // MARK: Actions

    /// Ajoute des fichiers (les doublons sont ignorés). Renvoie le nombre de fichiers ajoutés.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let existing = Set(items.compactMap { $0.resolvedURL()?.standardizedFileURL })
        let new = urls
            .filter { !existing.contains($0.standardizedFileURL) }
            .compactMap { ShelfItem(url: $0) }
        guard !new.isEmpty else { return 0 }
        withAnimation(.snappy) {
            items = Array((new + items).prefix(Self.maxItems))
        }
        save()
        return new.count
    }

    func remove(_ item: ShelfItem) {
        withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
        save()
    }

    func clear() {
        withAnimation(.snappy) { items.removeAll() }
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

    // MARK: Affichage

    var compactPriority: ModulePriority {
        showInCompact && !items.isEmpty ? .low : .none
    }

    var expandedWidthWeight: CGFloat { 2 }

    func compactLeading() -> AnyView? {
        guard !items.isEmpty else { return nil }
        return AnyView(Image(systemName: "tray.full.fill").foregroundStyle(.white.opacity(0.85)))
    }

    func compactTrailing() -> AnyView? {
        guard !items.isEmpty else { return nil }
        return AnyView(Text("\(items.count)").monospacedDigit())
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
    static func added(_ count: Int) -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.green)),
            trailing: AnyView(Text("+\(count)").monospacedDigit().foregroundStyle(.green)),
            duration: .seconds(2)
        )
    }
}
