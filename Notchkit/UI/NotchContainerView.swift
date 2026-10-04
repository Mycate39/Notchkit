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

        HStack(spacing: 0) {
            leading
                .frame(width: NotchLayout.compactSideWidth - 12, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .frame(width: NotchLayout.compactSideWidth - 12, alignment: .trailing)
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

            modules(horizontalPadding: ear + 18)
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
        ModulePage.paginate(viewModel.manager.activeModules.map(ModuleBox.init))
    }

    private var header: some View {
        let pages = pages
        return HStack {
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
                                PageView(page: page)
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

/// Une page de l'encoche dépliée : ses cartes se partagent la largeur selon leur poids.
private struct PageView: View {
    let page: ModulePage

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let totalWeight = page.modules.reduce(0) { $0 + $1.weight }
            let available = proxy.size.width - spacing * CGFloat(page.modules.count - 1)

            HStack(spacing: spacing) {
                ForEach(page.modules) { box in
                    box.module.expandedView()
                        .frame(width: max(0, available * box.weight / totalWeight))
                        .frame(maxHeight: .infinity)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

/// Enveloppe identifiable pour itérer sur des modules hétérogènes dans un `ForEach`.
@MainActor
private struct ModuleBox: Identifiable {
    let module: any NotchModule
    let id: String
    let weight: CGFloat
    let systemImage: String

    init(_ module: any NotchModule) {
        self.module = module
        self.id = module.moduleID
        self.weight = max(0.5, module.expandedWidthWeight)
        self.systemImage = type(of: module).descriptor.systemImage
    }
}

/// Groupe de modules affichés ensemble sur une page.
@MainActor
private struct ModulePage: Identifiable {
    let id: Int
    let modules: [ModuleBox]

    static func paginate(_ boxes: [ModuleBox]) -> [ModulePage] {
        NotchLayout.paginate(weights: boxes.map(\.weight)).enumerated().map { index, indices in
            ModulePage(id: index, modules: indices.map { boxes[$0] })
        }
    }
}
