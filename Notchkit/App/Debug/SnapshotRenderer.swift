#if DEBUG
import AppKit
import SwiftUI

/// Outil de développement : dessine l'interface dans des images PNG (sans capture d'écran,
/// donc sans autorisation d'enregistrement de l'écran). Lancer l'app avec la variable
/// d'environnement `NOTCHKIT_SNAPSHOT=/chemin/du/dossier`.
///
/// Limite : les vues AppKit intégrées (égaliseur, étoile de Claude) n'apparaissent pas.
@MainActor
enum SnapshotRenderer {
    static func renderAll(to directory: URL, viewModel: NotchViewModel, settings: SettingsStore, manager: ModuleManager) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Encoche dépliée, page par page (contenu des cartes, hors zone défilante).
        for page in ModulePage.pages(from: manager) {
            save(PageView(page: page, viewModel: viewModel)
                    .frame(width: NotchLayout.expandedSize.width - 36, height: 140)
                    .padding(18)
                    .background(.black)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("encoche-page-\(page.id + 1).png"))
        }

        // Tous les widgets en taille « Mini », côte à côte.
        let minis = manager.activeModules
        save(HStack(spacing: 8) {
                ForEach(Array(minis.enumerated()), id: \.offset) { _, module in
                    module.miniView()
                        .environment(\.widgetSize, .mini)
                        .frame(width: 70, height: 140)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(12)
            .background(.black)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark),
             to: directory.appendingPathComponent("widgets-mini.png"))

        // Onglet Disposition des réglages.
        save(LayoutEditorContent(manager: manager)
                .frame(width: 620, height: 1100)
                .background(Color(nsColor: .windowBackgroundColor)),
             to: directory.appendingPathComponent("reglages-disposition.png"))
    }

    private static func save(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
#endif
