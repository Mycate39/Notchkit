import AppKit
import SwiftUI
import Observation

/// Module Presse-papiers : historique des derniers éléments copiés, à recopier d'un clic.
///
/// macOS ne prévient pas quand le presse-papiers change : on compare son compteur de
/// modifications deux fois par seconde (opération très légère, sans lire le contenu).
/// Le contenu n'est lu qu'après un changement. Sur macOS 26, cette lecture déclenche une
/// demande d'autorisation (« Coller depuis d'autres apps ») la première fois.
@MainActor
@Observable
final class ClipboardModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "clipboard",
        name: "Presse-papiers",
        summary: "Historique des derniers éléments copiés, à recopier d'un clic.",
        systemImage: "doc.on.clipboard",
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    static let maxItems = 50

    private(set) var items: [ClipboardItem] = []

    /// Conserver l'historique entre deux lancements de l'app.
    var keepHistory: Bool {
        didSet {
            UserDefaults.standard.set(keepHistory, forKey: Keys.keepHistory)
            save()
        }
    }

    private enum Keys {
        static let keepHistory = "module.clipboard.keepHistory"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    /// Compteur après notre propre écriture : on ne l'ajoute pas comme une nouvelle copie.
    @ObservationIgnored private var ownChangeCount: Int?

    /// Emplacement de l'historique (remplaçable dans les tests pour ne pas toucher aux vraies données).
    static var storageURLOverride: URL?

    private static var storageURL: URL {
        if let storageURLOverride { return storageURLOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit", isDirectory: true)
            .appendingPathComponent("clipboard-history.json")
    }

    init(context: ModuleContext) {
        self.context = context
        keepHistory = UserDefaults.standard.object(forKey: Keys.keepHistory) as? Bool ?? true
        if keepHistory, let data = try? Data(contentsOf: Self.storageURL) {
            items = (try? JSONDecoder().decode([ClipboardItem].self, from: data)) ?? []
        }
    }

    // MARK: Cycle de vie

    func start() {
        // Lancements automatisés : pas de lecture du presse-papiers (demande d'autorisation macOS).
        guard pollTask == nil, !AutomatedRun.isActive else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.checkPasteboard()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkPasteboard() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if count == ownChangeCount { return }
        guard let content = ClipboardReader.read() else { return }
        add(ClipboardItem(content: content, sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName))
    }

    // MARK: Historique

    /// Ajoute un élément en tête ; un contenu déjà présent remonte en tête (en gardant son épingle).
    func add(_ item: ClipboardItem) {
        var item = item
        if let existing = items.firstIndex(where: { $0.hasSameContent(as: item) }) {
            item.isPinned = items[existing].isPinned
            items.remove(at: existing)
        }
        items.insert(item, at: 0)
        items = ClipboardHistory.trimmed(items, limit: Self.maxItems)
        save()
    }

    /// Recopie un élément dans le presse-papiers (prêt à être collé avec ⌘V).
    func copy(_ item: ClipboardItem) {
        ClipboardReader.write(item.content)
        ownChangeCount = NSPasteboard.general.changeCount
        lastChangeCount = ownChangeCount ?? lastChangeCount
        // Remonte en tête de l'historique.
        add(ClipboardItem(content: item.content, sourceApp: item.sourceApp))
        context.presentAlert(NotchAlert(
            leading: AnyView(Image(systemName: "doc.on.clipboard.fill").foregroundStyle(.white)),
            trailing: AnyView(Text("Copié").foregroundStyle(.green)),
            duration: .seconds(1.5)
        ))
    }

    /// Garde l'encoche ouverte pendant une recherche.
    func holdExpanded(_ hold: Bool) {
        context.holdExpanded(hold)
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        items = ClipboardHistory.sorted(items)
        save()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Efface l'historique (les éléments épinglés sont conservés).
    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        save()
    }

    private func save() {
        let url = Self.storageURL
        guard keepHistory else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Autorisation de lecture du presse-papiers (macOS 15.4 et plus).
    var accessStatus: String? {
        guard #available(macOS 15.4, *) else { return nil }
        return switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: String(localized: "Accès au presse-papiers autorisé")
        case .alwaysDeny: String(localized: "Accès au presse-papiers refusé : autorisez Notchkit dans Réglages Système > Confidentialité et sécurité > Coller depuis d'autres apps.")
        case .ask: String(localized: "macOS demandera l'autorisation lors de la prochaine copie.")
        default: nil
        }
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { .none }

    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "doc.on.clipboard", value: "\(items.count)", caption: String(localized: "Copies")))
    }

    func expandedView() -> AnyView {
        AnyView(ClipboardExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(ClipboardSettingsView(module: self))
    }
}

/// Règles de l'historique (logique pure, testée).
enum ClipboardHistory {
    /// Épinglés d'abord (dans leur ordre), puis les autres du plus récent au plus ancien.
    static func sorted(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    /// Limite le nombre d'éléments non épinglés (les épinglés ne sont jamais retirés).
    static func trimmed(_ items: [ClipboardItem], limit: Int) -> [ClipboardItem] {
        let ordered = sorted(items)
        let pinned = ordered.filter(\.isPinned)
        let others = ordered.filter { !$0.isPinned }.prefix(max(0, limit - pinned.count))
        return pinned + others
    }
}

#if DEBUG
extension ClipboardModule {
    /// Historique fictif pour les images de démonstration (non enregistré).
    func debugSetItems(_ items: [ClipboardItem]) {
        self.items = items
    }
}
#endif
