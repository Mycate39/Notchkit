import AppKit
import UniformTypeIdentifiers

/// Configuration partageable (fichier `.notchkit`) : widgets affichés, disposition des pages, apparence
/// et mascotte. Rien de personnel : ni réglages système, ni intégrations, ni données des widgets.
struct NotchkitProfile: Codable, Equatable, Sendable {
    static let fileExtension = "notchkit"
    static let format = 1

    var format = NotchkitProfile.format
    /// Widgets affichés (seuls les modules qui ont une carte : les intégrations restent celles de chacun).
    var widgets: [String: Bool] = [:]
    var widgetLayout: WidgetLayout?
    var appearance = NotchAppearance()
    var mascot: MascotDesign = .pip

    /// `widgets` : état réel de chaque widget (y compris ceux restés à leur valeur par défaut).
    init(settings: AppSettings, widgets: [String: Bool]) {
        self.widgets = widgets
        widgetLayout = settings.widgetLayout
        appearance = settings.appearance
        mascot = settings.mascot
    }

    /// Réglages après application : seuls les widgets connus de cette version sont touchés.
    func applied(to settings: AppSettings, widgetIDs: Set<String>) -> AppSettings {
        var result = settings
        for id in widgetIDs {
            result.moduleEnabled[id] = widgets[id] ?? false
        }
        result.widgetLayout = widgetLayout.map { layout in
            WidgetLayout(pages: layout.pages.map { $0.filter(widgetIDs.contains) }.filter { !$0.isEmpty },
                         sizes: layout.sizes.filter { widgetIDs.contains($0.key) })
        }
        result.appearance = appearance
        result.mascot = mascot
        return result
    }

    // Décodage tolérant : un fichier d'une autre version garde ce qu'il a de lisible.
    enum CodingKeys: String, CodingKey { case format, widgets, widgetLayout, appearance, mascot }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decodeIfPresent(Int.self, forKey: .format)) ?? Self.format
        widgets = (try? c.decodeIfPresent([String: Bool].self, forKey: .widgets)) ?? [:]
        widgetLayout = try? c.decodeIfPresent(WidgetLayout.self, forKey: .widgetLayout)
        appearance = (try? c.decodeIfPresent(NotchAppearance.self, forKey: .appearance)) ?? NotchAppearance()
        mascot = (try? c.decodeIfPresent(MascotDesign.self, forKey: .mascot)) ?? .pip
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> NotchkitProfile {
        try JSONDecoder().decode(NotchkitProfile.self, from: data)
    }
}

extension UTType {
    /// Type déclaré dans l'Info.plist (`UTExportedTypeDeclarations`).
    static let notchkitProfile = UTType(exportedAs: "com.andeolchenaux.notchkit.profile", conformingTo: .json)
}

/// Export et import d'une configuration, depuis les réglages ou en ouvrant un fichier `.notchkit`.
@MainActor
enum ProfileSharing {
    static func export(_ manager: ModuleManager) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.notchkitProfile]
        panel.nameFieldStringValue = String(localized: "Ma configuration Notchkit") + "." + NotchkitProfile.fileExtension
        panel.message = String(localized: "Widgets, disposition, apparence et mascotte. Partagez ce fichier : un double clic l'ouvre dans Notchkit.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try manager.profile().encoded().write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func chooseAndImport(_ manager: ModuleManager) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.notchkitProfile]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importProfile(at: url, into: manager)
    }

    /// Demande confirmation, puis applique la configuration (annulable depuis Disposition).
    static func importProfile(at url: URL, into manager: ModuleManager) {
        let profile: NotchkitProfile
        do {
            profile = try NotchkitProfile.decode(Data(contentsOf: url))
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Ce fichier n'est pas une configuration Notchkit lisible.")
            alert.runModal()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Appliquer « \(url.deletingPathExtension().lastPathComponent) » ?")
        alert.informativeText = String(localized: "Vos widgets, leur disposition, l'apparence de l'encoche et la mascotte seront remplacés. Vous pourrez rétablir vos widgets depuis Réglages > Disposition.")
        alert.addButton(withTitle: String(localized: "Appliquer"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.apply(profile)
    }
}
