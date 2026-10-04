import SwiftUI

/// Vue racine affichée dans le panneau : la forme noire et son contenu
/// (compact quand l'encoche est repliée, étendu quand elle est dépliée).
struct NotchContainerView: View {
    let viewModel: NotchViewModel

    var body: some View {
        let geometry = viewModel.geometry
        let size = viewModel.shapeSize
        let radii = NotchLayout.cornerRadii(for: geometry.style, isExpanded: viewModel.isExpanded, height: size.height)
        let shape = NotchShape(
            earRadius: geometry.style == .notch ? NotchLayout.earRadius : 0,
            topCornerRadius: radii.top,
            bottomCornerRadius: radii.bottom
        )

        ZStack(alignment: .top) {
            if viewModel.isExpanded {
                ExpandedNotchView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else {
                CompactNotchView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .contentShape(shape)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.top, NotchLayout.topInset(for: geometry.style))
        // La fenêtre peut être plus grande que la forme (pendant le repli) : on reste centré en haut.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Les modules changent de priorité sans passer par le view model : on anime ces changements ici.
        .animation(NotchLayout.spring, value: viewModel.hasCompactContent)
    }
}

// MARK: - Mode compact

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
        } else {
            compactRow(ear: ear, leading: leading, trailing: trailing)
        }
    }

    private func compactRow(ear: CGFloat, leading: AnyView?, trailing: AnyView?) -> some View {
        HStack(spacing: 0) {
            leading
                .frame(width: viewModel.compactSideWidth - 12, alignment: .leading)
            Spacer(minLength: 0)
            trailing
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
            // On reste sur la page où l'on était, sauf si un module réclame l'attention
            // (Claude au travail, rendez-vous imminent…) : on ouvre alors directement sa page.
            if let module = viewModel.manager.compactModule, module.compactPriority >= .elevated,
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
                // Onglets : un par page, avec les icônes des modules qu'elle contient.
                HStack(spacing: 6) {
                    ForEach(pages) { page in
                        Button {
                            withAnimation(NotchLayout.spring) { viewModel.selectedPage = page.id }
                        } label: {
                            HStack(spacing: 5) {
                                ForEach(page.modules) { box in
                                    Image(systemName: box.systemImage)
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(viewModel.selectedPage == page.id ? 0.18 : 0), in: Capsule())
                            .foregroundStyle(.white.opacity(viewModel.selectedPage == page.id ? 1 : 0.5))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            let spacing: CGFloat = 12
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
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: stacked ? 11 : 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
