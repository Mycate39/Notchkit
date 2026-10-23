import SwiftUI

/// Vue racine affichée dans le panneau : la forme noire et son contenu
/// (compact quand l'encoche est repliée, étendu quand elle est dépliée).
struct NotchContainerView: View {
    let viewModel: NotchViewModel

    private var shadow: NotchLayout.Shadow {
        if viewModel.isExpanded { return NotchLayout.expandedShadow }
        if viewModel.showsHoverShadow { return NotchLayout.hoverShadow }
        return NotchLayout.Shadow(opacity: 0, radius: 0, y: 0)
    }

    var body: some View {
        let geometry = viewModel.geometry
        let size = viewModel.shapeSize
        let island = viewModel.isIsland
        let radii = NotchLayout.cornerRadii(for: geometry.style, isExpanded: viewModel.isExpanded, height: size.height,
                                            island: island)
        // Alerte agrandie qui demande ses propres coins (carré Face ID).
        let alertRadius = viewModel.isExpanded ? nil : viewModel.currentAlert?.expandedCornerRadius
        let shape = NotchShape(
            earRadius: geometry.style == .notch ? NotchLayout.earRadius : 0,
            topCornerRadius: radii.top,
            bottomCornerRadius: alertRadius ?? radii.bottom
        )

        // Contenu dans un cadre fixe et persistant, isolé par `geometryGroup` : pendant que la forme
        // grandit (et dépasse, avec le ressort rebondissant), ce cadre reste centré sur l'encoche et la
        // forme le dévoile depuis le centre. Sans lui, le contenu inséré à l'ouverture suivait le bord
        // gauche de la forme animée.
        let expanded = NotchLayout.shapeSize(for: geometry, isExpanded: true, hasCompactContent: true)
        ZStack(alignment: .top) {
            if viewModel.isExpanded {
                ExpandedNotchView(viewModel: viewModel)
                    .frame(width: expanded.width, height: expanded.height)
                    .transition(.materialize)
            } else {
                CompactNotchView(viewModel: viewModel)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.opacity)
            }
        }
        .frame(width: max(expanded.width, size.width), height: max(expanded.height, size.height), alignment: .top)
        .geometryGroup()
        .frame(width: size.width, height: size.height, alignment: .top)
        .notchBackground(viewModel.appearance, style: geometry.style, shape: shape)
        // Fin contour gris, comme la Dynamic Island : pour l'île, et quand la barre des menus est
        // sombre (l'encoche noire s'y confondrait). Collée au bord de l'écran, pas de trait en haut.
        .overlay {
            shape.stroke(NotchLayout.keyLine(viewModel.keyLineColor)
                            .opacity((island && geometry.style == .pill) || viewModel.showsOutline ? 1 : 0),
                         lineWidth: 2)
                .mask(alignment: .top) {
                    Rectangle().padding(.top, geometry.style == .notch ? 2 : 0)
                }
        }
        .clipShape(shape)
        .contentShape(shape)
        // Profondeur : petite ombre au survol, ombre plus large une fois ouverte
        // (une grande surface paraît plus épaisse qu'une petite).
        .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        // Indice au survol : l'encoche gonfle légèrement, depuis le haut, avant de s'ouvrir.
        .scaleEffect(viewModel.showsHoverShadow ? 1.03 : 1, anchor: .top)
        // Vraie encoche au repos : rien par-dessus, l'encoche de l'écran suffit (bords nets).
        // Apparition immédiate ; disparition une fois le repli terminé, pour qu'on le voie.
        // Animation limitée à l'opacité : le repli lui-même garde son ressort, sans délai.
        .animation(viewModel.showsShape ? NotchLayout.spring : NotchLayout.shapeFadeOut) { content in
            content.opacity(viewModel.showsShape ? 1 : 0)
        }
        // Autres activités en cours : petites bulles à droite, comme sur iPhone.
        .overlay(alignment: .topTrailing) {
            CompactBubbles(viewModel: viewModel)
                // Décalage fixe (pas selon le nombre de bulles) : une bulle qui remonte ne doit pas
                // aussi glisser de côté.
                .offset(x: NotchLayout.bubblesWidth(count: 1, geometry: geometry, island: island))
        }
        .foregroundStyle(.white)
        .tint(viewModel.appearance.accentColor)
        .environment(\.onAccent, viewModel.appearance.onAccentColor)
        .environment(\.sliderTint, viewModel.appearance.sliderColor?.color)
        .environment(\.colorScheme, .dark)
        // Écran verrouillé : activités visibles, mais aucun bouton ni bulle cliquable.
        .allowsHitTesting(!viewModel.isScreenLocked)
        .padding(.top, NotchLayout.topInset(for: geometry.style))
        // La fenêtre peut être plus grande que la forme (pendant le repli) : on reste centré en haut.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Les modules changent de priorité sans passer par le view model : on anime ces changements ici.
        .animation(NotchLayout.spring, value: viewModel.hasCompactContent)
        .animation(NotchLayout.spring, value: island)
        .animation(NotchLayout.spring, value: viewModel.bubbleModules.map(\.moduleID))
    }
}

// MARK: - Mode compact

/// Activités secondaires, à droite de l'encoche repliée (comme sur iPhone).
/// - une seule : une bulle (mini-encoche en mode encoche) ;
/// - deux ou plus : une pile avec leur nombre. Au survol, elle se déroule en colonne de bulles
///   rondes, la pile devenant elle-même la première bulle.
/// Survoler (ou cliquer) une bulle ouvre l'encoche sur la page de son activité.
private struct CompactBubbles: View {
    let viewModel: NotchViewModel
    @Namespace private var namespace
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        let geometry = viewModel.geometry
        let island = viewModel.isIsland
        let diameter = NotchLayout.bubbleDiameter(for: geometry, island: island)
        let width = NotchLayout.bubbleWidth(for: geometry, island: island)
        let ids = viewModel.bubbleModules.map(\.moduleID)
        // Au repos : mini-encoche en mode encoche, bulle ronde sur la pastille.
        let resting: AnyShape = geometry.style == .notch
            ? AnyShape(NotchShape(earRadius: NotchLayout.earRadius, topCornerRadius: 0,
                                  bottomCornerRadius: min(10, diameter / 3)))
            : AnyShape(Capsule())

        ZStack(alignment: .topLeading) {
            if !ids.isEmpty {
                Group {
                    if ids.count >= 2 {
                        stack(ids, diameter: diameter, width: width, resting: resting)
                    } else if let id = ids.first {
                        bubble(id, diameter: diameter, width: width, shape: resting)
                            .onHover { hover(id, inside: $0) }
                    }
                }
                // La bulle descend du haut de l'écran et y remonte en disparaissant (le bord de la
                // fenêtre, collé en haut de l'écran, la masque au-dessus).
                .transition(.offset(y: -(diameter + NotchLayout.topInset(for: geometry.style) + 2)))
            }
        }
        .padding(.leading, NotchLayout.bubbleGap)
        .foregroundStyle(.white)
        .font(.system(size: 11, weight: .semibold))
    }

    // MARK: Pile et menu déroulant

    @ViewBuilder
    private func stack(_ ids: [String], diameter: CGFloat, width: CGFloat, resting: AnyShape) -> some View {
        let isOpen = viewModel.isBubbleMenuOpen
        VStack(spacing: NotchLayout.bubbleGap) {
            if isOpen {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    // La première reste suspendue au bord de l'écran, comme au repos ; les suivantes
                    // descendent en dessous, rondes.
                    bubble(id, diameter: diameter, width: index == 0 ? width : diameter,
                           shape: index == 0 ? resting : AnyShape(Capsule()), hanging: index == 0)
                        // La première bulle naît de la pile (même emplacement, la forme s'arrondit).
                        .matchedGeometryEffect(id: index == 0 ? "pile" : id, in: namespace)
                        .onHover { hover(id, inside: $0) }
                        // Les suivantes tombent l'une après l'autre, avec un léger décalage.
                        .transition(index == 0 ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.5, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -diameter * 0.6))
                                .animation(NotchLayout.spring.delay(Double(index) * 0.04)),
                            removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                        ))
                }
            } else {
                pile(ids, diameter: diameter, width: width, shape: resting)
                    .matchedGeometryEffect(id: "pile", in: namespace)
                    .transition(.opacity)
            }
        }
        .frame(width: width, alignment: .top)
        // Les espaces entre les bulles comptent pour le survol. En arrière-plan et non en
        // `contentShape` de la colonne : celui-ci limiterait aussi les clics à la largeur d'une bulle,
        // et les commandes qui débordent à droite (pause, ×) ne recevraient plus rien.
        .background { Color.clear.contentShape(Rectangle()) }
        .onHover { hoverMenu($0) }
        .animation(NotchLayout.spring, value: isOpen)
    }

    private func hoverMenu(_ inside: Bool) {
        closeTask?.cancel()
        if inside {
            viewModel.setBubbleMenuOpen(true)
        } else {
            // Petit délai : passer d'une bulle à l'autre (ou à ses commandes) ne referme pas le menu.
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                viewModel.setBubbleMenuOpen(false)
            }
        }
    }

    /// Survol d'une bulle : elle s'allonge vers la droite avec ses commandes si elle en a, sinon l'encoche s'ouvre sur sa page.
    private func hover(_ id: String, inside: Bool) {
        if viewModel.manager.module(for: id)?.bubbleControls() != nil {
            viewModel.hoverBubbleControls(id, part: .bubble, inside: inside)
        } else {
            viewModel.hoverBubble(id, inside: inside)
        }
    }

    /// Pile repliée : l'activité la plus importante, et une colonne de points (un par activité,
    /// le premier plus marqué) le long de son bord gauche.
    private func pile(_ ids: [String], diameter: CGFloat, width: CGFloat, shape: AnyShape) -> some View {
        bubble(ids[0], diameter: diameter, width: width, shape: shape)
            .overlay(alignment: .leading) {
                VStack(spacing: NotchLayout.bubbleDotSpacing) {
                    ForEach(ids.indices, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(index == 0 ? 0.9 : 0.35))
                            .frame(width: NotchLayout.bubbleDotSize, height: NotchLayout.bubbleDotSize)
                    }
                }
                .padding(.leading, viewModel.geometry.style == .notch ? NotchLayout.earRadius + 5 : 5)
                .allowsHitTesting(false)
            }
            .help(Text("\(ids.count) activités en cours"))
    }

    // MARK: Bulle

    /// Une bulle. Survolée, une bulle qui a des commandes (musique) s'allonge vers la droite pour
    /// les montrer ; sa place dans la mise en page ne change pas (elle déborde à droite).
    /// `hanging` : bulle suspendue au bord de l'écran (mini-encoche), sans contour en haut.
    private func bubble(_ id: String, diameter: CGFloat, width: CGFloat, shape: AnyShape,
                        hanging: Bool = true) -> some View {
        Group {
            if let module = viewModel.manager.module(for: id), let content = module.compactLeading() {
                let controls = viewModel.bubbleControlsID == id ? module.bubbleControls() : nil
                let icon = diameter * 0.62
                let ear = viewModel.geometry.style == .notch ? NotchLayout.earRadius : 0
                // Allongée : la pochette ne bouge pas, et les commandes se centrent entre elle et le bord droit.
                let iconEnd = (width + icon) / 2
                HStack(spacing: 0) {
                    content
                        .frame(width: icon, height: icon)
                        .frame(width: controls == nil ? width : iconEnd, height: diameter,
                               alignment: controls == nil ? .center : .trailing)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.expand(showing: id) }
                    if let controls {
                        controls
                            .frame(width: width + module.bubbleControlsWidth - iconEnd - ear, height: diameter)
                            // Mode encoche : les commandes restent à l'écart du congé de droite.
                            .padding(.trailing, ear)
                            // Les commandes débordent du cadre de la bulle : leur survol compte aussi, sinon
                            // elles se refermeraient avant qu'on atteigne le dernier bouton (×).
                            .contentShape(Rectangle())
                            .onHover { viewModel.hoverBubbleControls(id, part: .controls, inside: $0) }
                            .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                    }
                }
                    .notchBackground(viewModel.appearance, style: viewModel.geometry.style, shape: shape)
                    .overlay {
                        // Même fin contour que l'île : pastille flottante, menu déroulé, barre sombre.
                        if viewModel.geometry.style == .pill || viewModel.isBubbleMenuOpen || viewModel.showsOutline {
                            shape.stroke(NotchLayout.keyLine(module.keyLineColor), lineWidth: 2)
                                .mask(alignment: .top) {
                                    Rectangle().padding(.top, viewModel.geometry.style == .notch && hanging ? 2 : 0)
                                }
                        }
                    }
                    // Découpe après le contour, comme la grande encoche : seule sa moitié intérieure
                    // (1 pt) reste, au lieu d'un trait de 2 pt rogné par le bord de la fenêtre.
                    .clipShape(shape)
                    .contentShape(shape)
                    .help(Text(type(of: module).descriptor.name))
                    .accessibilityLabel(Text(type(of: module).descriptor.name))
            }
        }
        .frame(width: width, height: diameter, alignment: .leading)
    }
}

/// Contenu de l'encoche repliée : deux zones de part et d'autre de l'encoche physique.
private struct CompactNotchView: View {
    let viewModel: NotchViewModel

    var body: some View {
        let ear = viewModel.geometry.style == .notch ? NotchLayout.earRadius : 0
        let (leading, trailing) = content

        if let alert = viewModel.currentAlert, let expanded = alert.expandedContent {
            // Alerte agrandie : contenu centré sous la hauteur de l'encoche (ou dans toute la forme).
            VStack(spacing: 0) {
                Color.clear.frame(height: alert.centersExpandedContent ? 0 : viewModel.geometry.closedSize.height)
                expanded
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        } else if viewModel.isIsland {
            islandRow(leading: leading, trailing: trailing)
        } else {
            compactRow(ear: ear, leading: leading, trailing: trailing)
        }
    }

    /// Île : contenu à hauteur fixe (≈ 60 % de la capsule), marges égales sur les côtés.
    private func islandRow(leading: AnyView?, trailing: AnyView?) -> some View {
        let height = viewModel.shapeSize.height
        let content = (height * 0.6).rounded()
        return HStack(spacing: 0) {
            leading
                .frame(height: content)
            Spacer(minLength: 0)
            trailing
                .frame(height: content)
        }
        .padding(.horizontal, (height - content) / 2 + 3)
        .frame(height: height)
    }

    private func compactRow(ear: CGFloat, leading: AnyView?, trailing: AnyView?) -> some View {
        // Hauteur du contenu bornée : les vues extensibles (pochette, barres) gardent une taille
        // raisonnable quelle que soit la hauteur de l'encoche (barre des menus ou encoche réelle).
        let contentHeight = min(22, max(14, viewModel.geometry.closedSize.height - 4))
        return HStack(spacing: 0) {
            leading
                .frame(maxHeight: contentHeight)
                .frame(width: viewModel.compactSideWidth - 12, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .frame(maxHeight: contentHeight)
                .frame(width: viewModel.compactSideWidth - 12, alignment: .trailing)
        }
        .padding(.horizontal, ear + 10)
        .frame(height: viewModel.geometry.closedSize.height)
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        // Toutes les activités ont la largeur de la musique : un texte trop long rétrécit au lieu d'être coupé.
        .minimumScaleFactor(0.6)
    }

    /// Une alerte en cours passe avant le module compact.
    private var content: (AnyView?, AnyView?) {
        if let alert = viewModel.currentAlert {
            return (alert.leading, alert.trailing)
        }
        if let module = viewModel.manager.compactModule {
            return (module.compactLeading(), module.compactTrailing())
        }
        return (nil, nil)
    }
}

// MARK: - Mode déplié

/// Contenu de l'encoche dépliée : barre d'en-tête puis les vues étendues des modules actifs.
private struct ExpandedNotchView: View {
    let viewModel: NotchViewModel
    @Environment(\.onAccent) private var onAccent
    /// La pastille de la page affichée glisse d'un point à l'autre.
    @Namespace private var pageIndicator
    /// L'indicateur de pages n'apparaît que pendant un balayage, puis s'efface.
    @State private var showsPageIndicator = false
    @State private var hidePageIndicatorTask: Task<Void, Never>?
    /// Balayage des pages au trackpad.
    @State private var swiper = PageSwiper()

    var body: some View {
        let ear = viewModel.geometry.style == .notch ? NotchLayout.earRadius : 0

        VStack(spacing: 0) {
            header
                .frame(height: max(viewModel.geometry.closedSize.height, 28))
                .padding(.horizontal, ear + 18)

            Group {
                if viewModel.isDropMode {
                    DropZonesView(hovered: viewModel.hoveredDropZone, zones: viewModel.dropZones)
                        .padding(.horizontal, ear + 18)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    modules(horizontalPadding: ear + 18)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 16)
                .padding(.top, 4)
        }
        .onAppear {
            // Bulle cliquée : on ouvre la page de son widget (ex. Claude Code → page Agents).
            if let requested = viewModel.requestedModuleID {
                viewModel.requestedModuleID = nil
                let target = viewModel.manager.module(for: requested)?.widgetModuleID ?? requested
                if let page = pages.first(where: { $0.modules.contains { $0.id == target } }) {
                    viewModel.selectedPage = page.id
                    return
                }
            }
            // Une activité est affichée dans l'encoche repliée (musique, minuteur, Claude…) :
            // on ouvre directement la page de son widget. Sinon, on reste sur la page où l'on était.
            if let module = viewModel.manager.compactModule, module.compactPriority >= .normal,
               let page = pages.first(where: { $0.modules.contains { $0.id == module.widgetModuleID } }) {
                viewModel.selectedPage = page.id
            }
        }
    }

    private var pages: [ModulePage] {
        ModulePage.pages(from: viewModel.manager)
    }

    private var header: some View {
        let pages = pages
        return HStack {
            if pages.count > 1 {
                // Indicateur de pages : la page affichée en pastille avec ses icônes,
                // les autres en petits points cliquables (reste compact même avec beaucoup de pages).
                HStack(spacing: 5) {
                    ForEach(pages) { page in
                        let isSelected = viewModel.selectedPage == page.id
                        Button {
                            withAnimation(NotchLayout.pageIndicatorSpring) { viewModel.selectedPage = page.id }
                        } label: {
                            pageTab(page, isSelected: isSelected)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.notch)
                        .help(Text(page.modules.map { String(localized: type(of: $0.module).descriptor.name) }.joined(separator: ", ")))
                    }
                }
                // Apparition depuis la gauche : légère croissance, flou qui se dissipe.
                .opacity(showsPageIndicator ? 1 : 0)
                .scaleEffect(showsPageIndicator ? 1 : 0.8, anchor: .leading)
                .blur(radius: showsPageIndicator ? 0 : 4)
                .allowsHitTesting(showsPageIndicator)
            } else {
                Text("Notchkit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button {
                viewModel.openSettings()
            } label: {
                // Engrenage seul, sans pastille ronde ; la zone cliquable garde la taille du bouton.
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.notch)
            .help("Réglages")
            .accessibilityLabel(Text("Réglages"))
        }
    }

    /// Onglet d'une page : la pastille ambre avec ses icônes pour la page affichée, un point sinon.
    @ViewBuilder
    private func pageTab(_ page: ModulePage, isSelected: Bool) -> some View {
        if isSelected {
            HStack(spacing: 6) {
                ForEach(page.modules.prefix(5)) { box in
                    ModuleIcon(symbol: box.systemImage)
                        .frame(height: 11)
                }
            }
            // Les icônes de la page arrivent floues et grossissent pendant que la pastille glisse.
            .modifier(PageIconsEntrance())
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                // Onglet choisi : pilule de la couleur d'accent (style StandBy).
                Capsule()
                    .fill(.tint)
                    .matchedGeometryEffect(id: "pastille", in: pageIndicator)
            }
            .foregroundStyle(onAccent)
        } else {
            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 6, height: 6)
                .padding(5)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        }
    }

    /// Montre l'indicateur de pages ; il s'efface peu après, sauf tant que `holding` (doigts sur le trackpad).
    private func revealPageIndicator(holding: Bool = false) {
        hidePageIndicatorTask?.cancel()
        if !showsPageIndicator {
            withAnimation(NotchLayout.pageIndicatorSpring) { showsPageIndicator = true }
        }
        guard !holding else { return }
        hidePageIndicatorTask = Task {
            try? await Task.sleep(for: NotchLayout.pageIndicatorLinger)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) { showsPageIndicator = false }
        }
    }

    @ViewBuilder
    private func modules(horizontalPadding: CGFloat) -> some View {
        let pages = pages
        if pages.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 22))
                Text("Aucun module actif")
                    .font(.system(size: 13, weight: .medium))
                Text("Activez des modules dans les réglages.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else {
            // Pages côte à côte : balayage au trackpad (`PageSwiper`) ou clic sur les onglets.
            GeometryReader { proxy in
                let width = proxy.size.width
                let current = min(viewModel.selectedPage, pages.count - 1)
                HStack(spacing: 0) {
                    ForEach(pages) { page in
                        PageView(page: page, viewModel: viewModel)
                            .padding(.horizontal, horizontalPadding)
                            .frame(width: width, height: proxy.size.height)
                    }
                }
                .offset(x: -CGFloat(current) * width + swiper.swipe.offset(page: current, pageCount: pages.count))
                .frame(width: width, height: proxy.size.height, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .onAppear { swiper.pageWidth = width }
                .onChange(of: width) { _, new in swiper.pageWidth = new }
            }
            .onAppear { startSwiping() }
            .onDisappear { swiper.stop() }
        }
    }

    /// Branche le balayage : les pages suivent les doigts, puis se calent au relâchement.
    private func startSwiping() {
        swiper.start(
            pageCount: { pages.count },
            currentPage: { min(viewModel.selectedPage, max(0, pages.count - 1)) },
            onTrackingChange: { tracking in revealPageIndicator(holding: tracking) },
            onEnd: { target in
                withAnimation(NotchLayout.spring) { swiper.settle() }
                guard target != viewModel.selectedPage else { return }
                // Le cran a déjà été joué pendant le geste.
                viewModel.skipNextPageHaptic = true
                withAnimation(NotchLayout.spring) { viewModel.selectedPage = target }
            }
        )
    }
}

/// Entrée des icônes de la pastille : floues et réduites, elles se précisent avec un ressort.
private struct PageIconsEntrance: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1 : 0.6)
            .blur(radius: appeared ? 0 : 3)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(NotchLayout.pageIndicatorSpring.delay(0.05)) { appeared = true }
            }
    }
}

/// Reçoit les gestes du trackpad au-dessus de l'encoche (moniteur d'événements local : le panneau
/// n'est jamais la fenêtre active, mais le défilement va toujours à la fenêtre sous le pointeur).
@MainActor
@Observable
final class PageSwiper {
    private(set) var swipe = PageSwipe()
    @ObservationIgnored var pageWidth: CGFloat = 0
    @ObservationIgnored private var monitor: Any?
    /// Le dernier geste était pour les pages : son inertie est ignorée aussi.
    @ObservationIgnored private var lastGestureWasPaging = false
    /// Le geste en cours a commencé sur une vue qui défile elle-même à l'horizontale.
    @ObservationIgnored private var gestureBelongsToView = false
    /// Page visée lors du dernier cran haptique du geste en cours.
    @ObservationIgnored private var hapticTarget: Int?

    private static func isOverScrollCatcher(_ event: NSEvent) -> Bool {
        guard let content = event.window?.contentView else { return false }
        let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return content.hitTest(point) is ScrollCatcherView
    }

    func start(pageCount: @escaping @MainActor () -> Int, currentPage: @escaping @MainActor () -> Int,
               onTrackingChange: @escaping @MainActor (Bool) -> Void, onEnd: @escaping @MainActor (Int) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, event.window is NotchPanel else { return false }
                return self.handle(event, pageCount: pageCount(), currentPage: currentPage(),
                                   onTrackingChange: onTrackingChange, onEnd: onEnd)
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        swipe.begin()
    }

    /// Remet les pages en place après le calage (appelé dans une animation).
    func settle() { swipe.begin() }

    /// Renvoie `true` si l'événement est consommé par le balayage des pages.
    private func handle(_ event: NSEvent, pageCount: Int, currentPage: Int,
                        onTrackingChange: (Bool) -> Void, onEnd: (Int) -> Void) -> Bool {
        // Inertie après le relâchement : une page par geste.
        if !event.momentumPhase.isEmpty { return lastGestureWasPaging }
        // Molette de souris (sans phase) : laissée aux vues.
        guard !event.phase.isEmpty, event.hasPreciseScrollingDeltas else { return false }
        if event.phase.contains(.began) {
            swipe.begin()
            lastGestureWasPaging = false
            // Geste commencé sur une vue qui défile à l'horizontale (règle du minuteur) : il est pour elle.
            gestureBelongsToView = Self.isOverScrollCatcher(event)
        }
        if gestureBelongsToView { return false }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard swipe.isTracking else { return false }
            var final = swipe
            let target = final.end(page: currentPage, pageCount: pageCount, pageWidth: pageWidth)
            onTrackingChange(false)
            onEnd(target)
            return true
        }
        guard event.phase.contains(.began) || event.phase.contains(.changed) else { return false }
        let wasTracking = swipe.isTracking
        guard pageCount > 1 || swipe.isTracking else { return false }
        let consumed = swipe.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        if swipe.isTracking {
            lastGestureWasPaging = true
            if !wasTracking {
                hapticTarget = currentPage
                onTrackingChange(true)
            }
            // Cran haptique dès que le geste franchit le seuil de changement de page, doigts encore
            // posés : au relâchement, le trackpad ne vibre plus (le doigt est déjà levé).
            let target = swipe.target(page: currentPage, pageCount: pageCount, pageWidth: pageWidth)
            if target != hapticTarget {
                hapticTarget = target
                Haptics.play(.snap)
            }
        }
        return consumed
    }
}

/// Une page de l'encoche dépliée : ses cartes se partagent la largeur selon leur taille.
struct PageView: View {
    let page: ModulePage
    let viewModel: NotchViewModel

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 10
            let columns = WidgetColumns.make(sizes: page.modules.map(\.size))
            let columnWeights = columns.map { page.modules[$0[0]].size.weight }
            let totalWeight = max(0.001, columnWeights.reduce(0, +))
            let available = proxy.size.width - spacing * CGFloat(max(0, columns.count - 1))

            HStack(spacing: spacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    VStack(spacing: 8) {
                        ForEach(column, id: \.self) { position in
                            card(page.modules[position], stacked: column.count == 2)
                        }
                    }
                    .frame(width: max(0, available * columnWeights[index] / totalWeight))
                }
            }
        }
    }

    private func card(_ box: ModuleBox, stacked: Bool) -> some View {
        Group {
            if box.size == .mini { box.module.miniView() } else { box.module.expandedView() }
        }
        .environment(\.widgetSize, box.size)
        .environment(\.miniStacked, stacked)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Carte : fond discret, liseré éclairé par le haut.
        .notchCard(cornerRadius: stacked ? 12 : 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu { WidgetContextMenu(box: box, viewModel: viewModel) }
    }
}

/// Menu du clic droit sur un widget : taille, déplacement, masquage.
private struct WidgetContextMenu: View {
    let box: ModuleBox
    let viewModel: NotchViewModel

    private var manager: ModuleManager { viewModel.manager }

    var body: some View {
        let position = manager.position(of: box.id)
        let pages = manager.layoutPageIDs

        Picker("Taille", selection: Binding(
            get: { box.size },
            set: { manager.setSize($0, for: box.id) }
        )) {
            ForEach(WidgetSize.allCases) { size in
                Text(size.title).tag(size)
            }
        }

        Divider()

        if let position {
            Button("Déplacer à gauche") {
                manager.move(box.id, toPage: position.page, index: position.index - 1)
            }
            .disabled(position.index == 0)

            Button("Déplacer à droite") {
                manager.move(box.id, toPage: position.page, index: position.index + 2)
            }
            .disabled(position.index >= pages[position.page].count - 1)

            Button("Page précédente") {
                manager.move(box.id, toPage: position.page - 1, index: .max)
                viewModel.selectedPage = max(0, position.page - 1)
            }
            .disabled(position.page == 0)

            let isLastPage = position.page >= pages.count - 1
            Button(isLastPage ? "Nouvelle page" : "Page suivante") {
                manager.move(box.id, toPage: position.page + 1, index: .max)
                viewModel.selectedPage = position.page + 1
            }
            .disabled(isLastPage && pages[position.page].count == 1)
        }

        Divider()

        if manager.contextualIDs.contains(box.id) {
            // Widget apparu de lui-même (masqué, mais avec du contenu) : on peut le garder pour de bon.
            Button("Ajouter à la disposition") {
                manager.enable(box.id, atPage: max(0, pages.count - 1), index: .max)
            }
        } else {
            Button("Masquer ce widget") {
                manager.setEnabled(false, for: box.id)
            }
        }
        Button("Modifier la disposition…") {
            viewModel.openSettings(tab: .layout)
        }
    }
}

/// Enveloppe identifiable pour itérer sur des modules hétérogènes dans un `ForEach`.
@MainActor
struct ModuleBox: Identifiable {
    let module: any NotchModule
    let id: String
    let size: WidgetSize
    let systemImage: String
}

/// Groupe de modules affichés ensemble sur une page.
@MainActor
struct ModulePage: Identifiable {
    let id: Int
    let modules: [ModuleBox]

    static func pages(from manager: ModuleManager) -> [ModulePage] {
        let modules = Dictionary(uniqueKeysWithValues: manager.activeModules.map { ($0.moduleID, $0) })
        return manager.pageIDs.enumerated().map { index, ids in
            ModulePage(id: index, modules: ids.compactMap { id in
                modules[id].map { module in
                    ModuleBox(module: module, id: id, size: manager.size(for: id),
                              systemImage: type(of: module).descriptor.systemImage)
                }
            })
        }
    }
}

// MARK: - Taille du widget dans l'environnement SwiftUI

extension EnvironmentValues {
    /// Taille du widget en cours d'affichage : les vues des modules s'y adaptent.
    @Entry var widgetSize: WidgetSize = .medium
    /// Widget Mini empilé (moitié de la hauteur) : disposition horizontale compacte.
    @Entry var miniStacked = false
}
