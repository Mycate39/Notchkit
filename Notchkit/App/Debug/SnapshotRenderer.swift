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

        // Minuteur façon iOS (un minuteur en cours) et sélecteur de durée.
        if let activities = manager.module(for: LiveActivitiesModule.descriptor.id) as? LiveActivitiesModule {
            activities.startTimer(seconds: 272)
            save(LiveActivitiesExpandedView(module: activities)
                    .environment(\.widgetSize, .large)
                    .frame(width: 300, height: 140)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .padding(12).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("minuteur-ios.png"))
            if let compactLeading = activities.compactLeading(), let compactTrailing = activities.compactTrailing() {
                save(HStack { compactLeading; Spacer(); compactTrailing }
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 330, height: 30).padding(.horizontal, 10)
                        .background(.black, in: Capsule()).padding(8).background(Color(white: 0.35)),
                     to: directory.appendingPathComponent("minuteur-compact.png"))
            }
            activities.activities.map(\.id).forEach(activities.remove)
        }

        // Animations de déverrouillage (première image de chacune).
        save(HStack(spacing: 16) {
                ForEach(0..<3) { index in
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 30)
                        Group {
                            switch index {
                            case 0: FaceIDUnlockView()
                            case 1: TouchIDPromptView()
                            default: PasswordPromptView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: UnlockAnimations.size.width, height: UnlockAnimations.size.height)
                    .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
                }
            }
            .padding(12).background(Color(white: 0.35)).foregroundStyle(.white).environment(\.colorScheme, .dark),
             to: directory.appendingPathComponent("deverrouillage.png"))

        // Mini empilés deux par deux.
        let stackedModules = Array(manager.activeModules.prefix(6))
        save(HStack(spacing: 8) {
                ForEach(0..<(stackedModules.count / 2), id: \.self) { column in
                    VStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { row in
                            stackedModules[column * 2 + row].miniView()
                                .environment(\.widgetSize, .mini)
                                .environment(\.miniStacked, true)
                                .frame(width: 70, height: 66)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
            }
            .padding(12).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark),
             to: directory.appendingPathComponent("widgets-mini-empiles.png"))

        // Visage de l'assistant, dans ses quatre humeurs.
        save(HStack(spacing: 18) {
                AssistantFace(mood: .idle, size: 80)
                AssistantFace(mood: .thinking, size: 80)
                AssistantFace(mood: .speaking, size: 80)
                AssistantFace(mood: .error, size: 80)
            }
            .padding(16).background(.black),
             to: directory.appendingPathComponent("assistant-visage.png"))

        // Icônes au trait et jauge de batterie en charge.
        save(HStack(spacing: 18) {
                LineGlyph(shape: BoltShape()).frame(width: 40, height: 40)
                LineGlyph(shape: PlugShape()).frame(width: 40, height: 40)
                LineGlyph(shape: MusicNoteShape()).frame(width: 40, height: 40)
                DefaultArtwork().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10))
                BatteryGlyph(level: 0.6, color: .green, showsBolt: true, size: CGSize(width: 54, height: 26))
                ClaudeMarkShape().fill(ClaudeMark.color).frame(width: 40, height: 40)
                    .padding(6).background(ClaudeMark.background, in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(16).background(.black).foregroundStyle(.white),
             to: directory.appendingPathComponent("icones.png"))

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
