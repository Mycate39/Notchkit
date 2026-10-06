import SwiftUI

/// Vue racine affichée dans le panneau : la forme noire et son contenu
/// (compact quand l'encoche est repliée, étendu quand elle est dépliée).
struct NotchContainerView: View {
    let viewModel: NotchViewModel

    private var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) {
        if viewModel.isExpanded { return (0.5, 16, 6) }
        if viewModel.showsHoverShadow { return (0.45, 5, 2) }
        return (0, 0, 0)
    }

    var body: some View {
        let geometry = viewModel.geometry
        let size = viewModel.shapeSize
        let island = viewModel.isIsland
        let radii = NotchLayout.cornerRadii(for: geometry.style, isExpanded: viewModel.isExpanded, height: size.height,
                                            island: island)
        let shape = NotchShape(
            earRadius: geometry.style == .notch ? NotchLayout.earRadius : 0,
            topCornerRadius: radii.top,
            bottomCornerRadius: radii.bottom
        )

        ZStack(alignment: .top) {
            if viewModel.isExpanded {
                ExpandedNotchView(viewModel: viewModel)
                    .transition(.materialize)
            } else {
                CompactNotchView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .notchBackground(viewModel.appearance, style: geometry.style, shape: shape)
        // Fin contour gris, comme la Dynamic Island : pour l'île, et quand la barre des menus est
        // sombre (l'encoche noire s'y confondrait). Collée au bord de l'écran, pas de trait en haut.
        .overlay {
            shape.stroke(.white.opacity((island && geometry.style == .pill) || viewModel.showsOutline ? 0.22 : 0),
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
        // Autres activités en cours : petites bulles à droite, comme sur iPhone.
        .overlay(alignment: .topTrailing) {
            CompactBubbles(viewModel: viewModel)
                .offset(x: NotchLayout.bubblesWidth(count: viewModel.bubbleModules.count, geometry: geometry, island: island))
        }
        .foregroundStyle(.white)
        .tint(viewModel.appearance.accentColor)
        .environment(\.colorScheme, .dark)
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
            : AnyShape(Circle())

        Group {
            if ids.count >= 2 {
                stack(ids, diameter: diameter, width: width, resting: resting)
            } else if let id = ids.first {
                bubble(id, diameter: diameter, width: width, shape: resting)
                    .onHover { viewModel.hoverBubble(id, inside: $0) }
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
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
                    bubble(id, diameter: diameter, width: diameter, shape: AnyShape(Circle()))
                        // La première bulle naît de la pile (même emplacement, la forme s'arrondit).
                        .matchedGeometryEffect(id: index == 0 ? "pile" : id, in: namespace)
                        .onHover { viewModel.hoverBubble(id, inside: $0) }
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
        // En mode encoche, le menu se détache légèrement du bord de l'écran.
        .padding(.top, isOpen && viewModel.geometry.style == .notch ? NotchLayout.bubbleMenuTopInset : 0)
        .frame(width: width, alignment: .top)
        .contentShape(Rectangle())
        .onHover { inside in
            closeTask?.cancel()
            if inside {
                viewModel.setBubbleMenuOpen(true)
            } else {
                // Petit délai : passer d'une bulle à l'autre ne referme pas le menu.
                closeTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    viewModel.setBubbleMenuOpen(false)
                }
            }
        }
        .animation(NotchLayout.spring, value: isOpen)
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    /// Pile repliée : l'activité la plus importante et le nombre d'activités rangées.
    private func pile(_ ids: [String], diameter: CGFloat, width: CGFloat, shape: AnyShape) -> some View {
        bubble(ids[0], diameter: diameter, width: width, shape: shape)
            .overlay(alignment: .bottomTrailing) {
                Text(verbatim: "\(ids.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(StandBy.onAccent)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(.tint, in: Capsule())
                    .offset(x: viewModel.geometry.style == .notch ? -NotchLayout.earRadius - 2 : 2, y: 1)
            }
            .help(Text("\(ids.count) activités en cours"))
    }

    // MARK: Bulle

    private func bubble(_ id: String, diameter: CGFloat, width: CGFloat, shape: AnyShape) -> some View {
        Group {
            if let module = viewModel.manager.module(for: id), let content = module.compactLeading() {
                content
                    .frame(width: diameter * 0.62, height: diameter * 0.62)
                    .frame(width: width, height: diameter)
                    .notchBackground(viewModel.appearance, style: viewModel.geometry.style, shape: shape)
                    .clipShape(shape)
                    .overlay {
                        // Même fin contour que l'île : pastille flottante, menu déroulé, barre sombre.
                        if viewModel.geometry.style == .pill || viewModel.isBubbleMenuOpen || viewModel.showsOutline {
                            shape.stroke(.white.opacity(0.22), lineWidth: 2)
                                .mask(alignment: .top) {
                                    Rectangle().padding(.top, viewModel.geometry.style == .notch
                                                        && !viewModel.isBubbleMenuOpen ? 2 : 0)
                                }
                        }
                    }
                    .contentShape(shape)
                    .onTapGesture { viewModel.expand(showing: id) }
                    .help(Text(type(of: module).descriptor.name))
            }
        }
    }
}

/// Contenu de l'encoche repliée : deux zones de part et d'autre de l'encoche physique.
private struct CompactNotchView: View {
    let viewModel: NotchViewModel

    var body: some View {
        let ear = viewModel.geometry.style == .notch ? NotchLayout.earRadius : 0
        let (leading, trailing) = content

        if let expanded = viewModel.currentAlert?.expandedContent {
            // Alerte agrandie : contenu centré sous la hauteur de l'encoche.
            VStack(spacing: 0) {
                Color.clear.frame(height: viewModel.geometry.closedSize.height)
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
    /// La pastille de la page affichée glisse d'un point à l'autre.
    @Namespace private var pageIndicator

    var body: some View {
        let ear = viewModel.geometry.style == .notch ? NotchLayout.earRadius : 0

        VStack(spacing: 0) {
            header
                .frame(height: max(viewModel.geometry.closedSize.height, 28))
                .padding(.horizontal, ear + 18)

            Group {
                if viewModel.isDropMode {
                    DropZonesView(hovered: viewModel.hoveredDropZone, shelfAvailable: viewModel.isShelfAvailable)
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
            // Bulle cliquée : on ouvre la page de son module.
            if let requested = viewModel.requestedModuleID {
                viewModel.requestedModuleID = nil
                if let page = pages.first(where: { $0.modules.contains { $0.id == requested } }) {
                    viewModel.selectedPage = page.id
                    return
                }
            }
            // Une activité est affichée dans l'encoche repliée (musique, minuteur, Claude…) :
            // on ouvre directement sa page. Sinon, on reste sur la page où l'on était.
            if let module = viewModel.manager.compactModule, module.compactPriority >= .normal,
               let page = pages.first(where: { $0.modules.contains { $0.id == module.moduleID } }) {
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
            // « ◀ App précédente », en haut à gauche comme sur iPhone.
            if let back = viewModel.manager.module(for: BackButtonModule.descriptor.id) as? BackButtonModule,
               let previous = back.previousApp {
                BackLink(name: previous.name, action: back.goBack)
                    .frame(maxWidth: 110, alignment: .leading)
                    .padding(.trailing, 4)
            }
            if pages.count > 1 {
                // Indicateur de pages : la page affichée en pastille avec ses icônes,
                // les autres en petits points cliquables (reste compact même avec beaucoup de pages).
                HStack(spacing: 5) {
                    ForEach(pages) { page in
                        let isSelected = viewModel.selectedPage == page.id
                        Button {
                            withAnimation(NotchLayout.spring) { viewModel.selectedPage = page.id }
                        } label: {
                            Group {
                                if isSelected {
                                    HStack(spacing: 6) {
                                        ForEach(page.modules.prefix(5)) { box in
                                            ModuleIcon(symbol: box.systemImage)
                                                .frame(height: 11)
                                        }
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background {
                                        // Onglet choisi : pilule ambre, icônes en noir chaud (style StandBy).
                                        Capsule()
                                            .fill(.tint)
                                            .matchedGeometryEffect(id: "pastille", in: pageIndicator)
                                    }
                                    .foregroundStyle(StandBy.onAccent)
                                } else {
                                    Circle()
                                        .fill(.white.opacity(0.35))
                                        .frame(width: 6, height: 6)
                                        .padding(5)
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.notch)
                        .help(Text(page.modules.map { String(localized: type(of: $0.module).descriptor.name) }.joined(separator: ", ")))
                    }
                }
            } else {
                Text("Notchkit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button {
                viewModel.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.standBy(.small, circle: true))
            .help("Réglages")
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
            // Pages défilantes : balayage horizontal au trackpad, ou clic sur les onglets.
            GeometryReader { proxy in
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(pages) { page in
                                PageView(page: page, viewModel: viewModel)
                                    .padding(.horizontal, horizontalPadding)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .id(page.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding(
                        get: { min(viewModel.selectedPage, pages.count - 1) },
                        set: { if let page = $0 { viewModel.selectedPage = page } }
                    ))
                    .onAppear {
                        // La vue est recréée à chaque ouverture : on replace explicitement le défilement
                        // sur la page mémorisée (la position initiale n'est pas toujours appliquée).
                        reader.scrollTo(min(viewModel.selectedPage, pages.count - 1), anchor: .leading)
                    }
                }
            }
        }
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
        let pages = manager.pageIDs

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

        Button("Masquer ce widget") {
            manager.setEnabled(false, for: box.id)
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
