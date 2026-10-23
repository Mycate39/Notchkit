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
                            case 0: TouchIDUnlockView()
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

        // Tutoriel de bienvenue : une image par étape.
        for step in OnboardingStep.allCases {
            save(OnboardingView(manager: manager, viewModel: viewModel, mascot: settings.settings.mascot,
                                openSettings: { _ in }, finish: {}, startAt: step)
                    .environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("tutoriel-\(step.rawValue + 1).png"))
        }

        // Lecteur de musique (grande carte) avec un morceau fictif.
        if let music = manager.module(for: MusicModule.descriptor.id) as? MusicModule {
            let artwork = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
                NSGradient(colors: [.systemPurple, .systemPink, .systemOrange])?.draw(in: rect, angle: 45)
                return true
            }
            var info = NowPlayingInfo(origin: .appleMusic, title: "Entropy", artist: "Beach Bunny", isPlaying: true)
            info.duration = 221
            info.elapsed = 170
            info.timestamp = Date()
            info.artwork = artwork
            info.artworkHash = 1
            music.debugSetNowPlaying(info)
            save(MusicExpandedView(module: music)
                    .environment(\.widgetSize, .large)
                    .frame(width: 420, height: 142)
                    .notchCard()
                    .padding(14).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
                    .tint(StandBy.defaultAccent.color),
                 to: directory.appendingPathComponent("musique-grande.png"))
            // Carte moyenne et carte basse (petite taille d'encoche) : la disposition se resserre.
            for (name, widgetSize, cardSize) in [("musique-moyenne", WidgetSize.medium, CGSize(width: 310, height: 142)),
                                                 ("musique-basse", WidgetSize.large, CGSize(width: 420, height: 112))] {
                save(MusicExpandedView(module: music)
                        .environment(\.widgetSize, widgetSize)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .notchCard()
                        .padding(14).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
                        .tint(StandBy.defaultAccent.color),
                     to: directory.appendingPathComponent("\(name).png"))
            }
            music.debugSetNowPlaying(nil)
        }

        // Contrôles du style StandBy (pilules, cercles, barre et curseur).
        save(VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("5 min") {}.buttonStyle(.standBy(.small))
                    Button("10 min") {}.buttonStyle(.standBy(.small))
                    Button {} label: { Image(systemName: "plus") }.buttonStyle(.standBy(.small, circle: true))
                    Button {} label: { Label("Démarrer", systemImage: "play.fill") }.buttonStyle(.standBy(.small, active: true))
                }
                HStack(spacing: 10) {
                    Button {} label: { Image(systemName: "pause.fill") }.buttonStyle(.standBy(.large, active: true, circle: true))
                    Button {} label: { Image(systemName: "xmark").fontWeight(.bold) }.buttonStyle(.standBy(.large, circle: true))
                    Button {} label: { Image(systemName: "gearshape.fill") }.buttonStyle(.standBy(.small, circle: true))
                }
                StandByBar(value: 0.62, height: 6).frame(width: 260)
                HStack(spacing: 8) {
                    Button {} label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.standBy(.regular, circle: true))
                    StandBySlider(value: .constant(0.45)).frame(width: 222)
                }
            }
            .padding(16).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
            .tint(StandBy.defaultAccent.color),
             to: directory.appendingPathComponent("standby-controles.png"))

        // Curseurs façon iOS : repos, glissement (loupe), couleur personnalisée, petite taille.
        save(VStack(alignment: .leading, spacing: 22) {
            SliderTrack(value: 0.45, height: 26, width: 240, isDragging: false)
            SliderTrack(value: 0.6, height: 26, width: 240, isDragging: true)
            SliderTrack(value: 0.7, height: 26, width: 240, isDragging: false).environment(\.sliderTint, .blue)
            SliderTrack(value: 0.3, height: 14, width: 240, isDragging: false)
        }
        .padding(24).background(.black).environment(\.colorScheme, .dark).tint(StandBy.defaultAccent.color),
             to: directory.appendingPathComponent("curseurs-verre.png"))

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

        // Jauges de batterie : niveaux, couleurs et tailles (encoche, carte, alerte).
        save(VStack(alignment: .leading, spacing: 14) {
                ForEach([CGSize(width: 25, height: 12), CGSize(width: 36, height: 17), CGSize(width: 54, height: 26)],
                        id: \.width) { size in
                    HStack(spacing: 18) {
                        BatteryGlyph(level: 0.98, color: .green, showsBolt: true, size: size)
                        BatteryGlyph(level: 0.45, color: .green, showsBolt: true, size: size)
                        BatteryGlyph(level: 0.71, color: .white, showsBolt: false, size: size)
                        BatteryGlyph(level: 0.6, color: .white, showsBolt: true, size: size)
                        BatteryGlyph(level: 0.5, color: .yellow, showsBolt: false, size: size)
                        BatteryGlyph(level: 0.08, color: .red, showsBolt: false, size: size)
                    }
                }
            }
            .padding(16).background(.black),
             to: directory.appendingPathComponent("batterie.png"))

        // Onglet Disposition des réglages.
        save(LayoutEditorContent(manager: manager)
                .frame(width: 620, height: 1100)
                .background(Color(nsColor: .windowBackgroundColor)),
             to: directory.appendingPathComponent("reglages-disposition.png"))

        // Propositions de mascotte : une ligne par personnage, une colonne par humeur.
        let moods: [(String, MascotMood, CGSize)] = [
            ("Repos", .idle, .zero), ("Regarde", .idle, CGSize(width: -1, height: -0.4)),
            ("Travaille", .working, CGSize(width: 0.6, height: 0.6)), ("Attend", .waiting, .zero),
            ("Contente", .happy, .zero), ("Fâchée", .angry, .zero),
        ]
        // Convertisseur : vide, un document, plusieurs images, résultat ; puis les zones de dépôt.
        let converter = ConverterModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
        let converterStates: [(String, () -> Void)] = [
            ("convertisseur-vide", { converter.clear() }),
            ("convertisseur-document", { converter.add([URL(fileURLWithPath: "/Users/moi/Documents/Rapport annuel.docx")]) }),
            ("convertisseur-images", { converter.add(["IMG_0042.HEIC", "IMG_0043.HEIC", "Plage.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }) }),
            ("convertisseur-resultat", { converter.debugSetResults([URL(fileURLWithPath: "/tmp/Rapport annuel.pdf")]) }),
            ("convertisseur-depot", { converter.isDropTargeted = true }),
        ]
        for (name, apply) in converterStates {
            apply()
            for (suffix, widgetSize, cardSize) in [("", WidgetSize.medium, CGSize(width: 310, height: 142)),
                                                   ("-petit", WidgetSize.small, CGSize(width: 200, height: 142))] {
                save(ConverterExpandedView(module: converter)
                        .environment(\.widgetSize, widgetSize)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .notchCard()
                        .padding(14).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
                        .tint(StandBy.defaultAccent.color),
                     to: directory.appendingPathComponent("\(name)\(suffix).png"))
            }
        }
        save(DropZonesView(hovered: .convert, zones: [.shelf, .convert, .airDrop])
                .frame(width: 520, height: 130)
                .padding(14).background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark),
             to: directory.appendingPathComponent("zones-depot.png"))

        // Page Agents : sans agent, au travail, puis en attente d'accord.
        let agents = AgentsModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in },
                                                         mascot: { settings.settings.mascot }))
        let now = Date()
        var working = ClaudeSession(id: "w", projectName: "notchkit", state: .working,
                                    prompt: "Ajoute le widget pleine page des agents", lastEventAt: now)
        let actions = [("doc.text.magnifyingglass", "Lit WidgetLayout.swift"), ("magnifyingglass", "Recherche « fullPage »"),
                       ("pencil", "Modifie ModuleManager.swift"), ("terminal", "Exécute : xcodebuild test")]
        working.recentActions = actions.enumerated().reversed().map { ClaudeAction(symbol: $1.0, text: $1.1, date: now.addingTimeInterval(Double($0))) }
        working.currentAction = working.recentActions.first
        working.phases = [.read, .edit]
        working.currentPhase = .edit
        working.lastEdit = ClaudeEdit(filePath: "/Users/moi/korus/src/invoice.ts",
                                      removed: ["const TVA = 0.196"],
                                      added: ["const TVA = 0.20 // 2026", "export const round = (n: number) =>", "  Math.round(n * 100) / 100"],
                                      firstLine: 12)
        working.lastEditAt = now.addingTimeInterval(-0.6)
        var testing = working
        testing.phases = [.read, .edit, .run]
        testing.currentPhase = .run
        testing.lastCommand = ClaudeCommand(command: "npm test", output: "PASS tests/invoice.test.ts\n  ✓ applique la TVA à 20 % (3 ms)\nTests: 48 passed, 48 total")
        testing.lastCommandAt = now
        var waiting = ClaudeSession(id: "p", projectName: "korus", state: .waitingForPermission,
                                    prompt: "Corrige le calcul de la TVA", lastEventAt: now.addingTimeInterval(5))
        waiting.attentionMessage = "Claude needs your permission to use Bash"
        waiting.permissionPrompt = ClaudePermissionPrompt(symbol: "terminal", text: "Exécute : supprimer node_modules",
                                                          detail: "rm -rf node_modules", canAlwaysAllow: true)
        var asking = ClaudeSession(id: "q", projectName: "korus", state: .waitingForPermission,
                                   prompt: "Ajoute un graphique des ventes", lastEventAt: now)
        asking.questionPrompt = ClaudeQuestionPrompt(input: ["questions": [[
            "question": "Pour le « mode jeu », qu'est-ce que tu imagines ?", "header": "Mode jeu", "multiSelect": true,
            "options": [["label": "Encoche discrète en jeu"], ["label": "Infos de jeu dans l'encoche"],
                        ["label": "Ne pas déranger"], ["label": "Bouton manuel"]],
        ], ["question": "Quelles périodes ?", "header": "Périodes", "multiSelect": true,
            "options": [["label": "Jour"], ["label": "Semaine"], ["label": "Mois"]]]]])
        for (name, sessions) in [("vide", [ClaudeSession]()), ("travail", [working]), ("commande", [testing]), ("attente", [waiting, working]), ("question", [asking])] {
            agents.previewSessions = sessions
            save(AgentsHomeView(module: agents)
                    .frame(width: 508, height: 123)
                    .notchCard(cornerRadius: 16)
                    .padding(18)
                    .background(.black)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("agents-\(name).png"))
        }

        // Question aux libellés longs, dans une vraie fenêtre (la rangée défile).
        agents.previewSessions = [asking]
        saveWindow(AgentsHomeView(module: agents)
                    .frame(width: 508, height: 123)
                    .padding(18)
                    .background(.black)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark),
                   size: CGSize(width: 544, height: 159),
                   to: directory.appendingPathComponent("agents-question-fenetre.png"))

        // Toutes les propositions sur une seule image : deux colonnes de personnages, numérotés.
        let all = MascotDesign.allBoards
        let half = (all.count + 1) / 2
        let column = { (designs: ArraySlice<MascotDesign>, offset: Int) in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text("").frame(width: 110)
                    ForEach(moods, id: \.0) { mood in
                        Text(mood.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                            .frame(width: 92)
                    }
                }
                ForEach(Array(designs.enumerated()), id: \.offset) { position, design in
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text("\(offset + position + 1)").font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.4)).frame(width: 22, alignment: .trailing)
                            Text(design.name).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(width: 110, alignment: .leading)
                        ForEach(moods, id: \.0) { mood in
                            MascotView(design: design, mood: mood.1, gaze: mood.2, size: 50)
                                .frame(width: 92, height: 84)
                        }
                    }
                }
            }
        }
        save(HStack(alignment: .top, spacing: 40) {
                column(all[0..<half], 0)
                column(all[half...], half)
            }
            .padding(28)
            .background(.black),
             to: directory.appendingPathComponent("mascotte-propositions.png"))

        // Égaliseur (vue AppKit) : agrandi pour vérifier les bouts arrondis des barres.
        saveWindow(HStack(spacing: 40) {
                EqualizerView(isAnimating: false, monitor: nil, color: .white).frame(width: 96, height: 72)
                EqualizerView(isAnimating: false, monitor: nil, color: .systemPink, bellShaped: true).frame(width: 96, height: 72)
            }
            .padding(30)
            .background(.black),
                   size: CGSize(width: 312, height: 132),
                   to: directory.appendingPathComponent("egaliseur.png"))

        // Fenêtre de réglages, onglet Widgets puis page d'un module (contrôles AppKit : rendu en fenêtre).
        let router = SettingsRouter()
        for (tab, name) in [(SettingsTab.widgets, "reglages-widgets"), (.module(MusicModule.descriptor.id), "reglages-widget-musique"), (.appearance, "reglages-apparence"), (.permissions, "reglages-autorisations"), (.module(AgentsModule.descriptor.id), "reglages-widget-agents")] {
            router.tab = tab
            saveWindow(SettingsView(settings: settings, manager: manager, router: router),
                       size: CGSize(width: 820, height: tab == .appearance ? 1300 : 620),
                       to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// Rendu d'une vue dans une vraie fenêtre (hors écran), pour les contrôles AppKit
    /// (formulaires, interrupteurs) qu'`ImageRenderer` ne dessine pas.
    private static func saveWindow(_ view: some View, size: CGSize, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.orderFrontRegardless()
        // Laisse SwiftUI mettre en page la barre latérale et la pile de navigation.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
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
