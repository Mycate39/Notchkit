import SwiftUI

/// Éditeur de disposition : chaque page de l'encoche est dessinée en miniature.
/// - glisser un widget le déplace (dans la page, vers une autre page, ou vers une nouvelle page) ;
/// - cliquer sur un widget permet de changer sa taille ou de le masquer ;
/// - glisser un widget masqué dans une page l'active.
struct LayoutSettingsView: View {
    let manager: ModuleManager

    var body: some View {
        ScrollView {
            LayoutEditorContent(manager: manager)
        }
    }
}

/// Contenu de l'éditeur (séparé de la zone défilante, pour pouvoir le dessiner seul).
struct LayoutEditorContent: View {
    let manager: ModuleManager

    private var descriptors: [String: ModuleDescriptor] {
        Dictionary(uniqueKeysWithValues: manager.orderedDescriptors.map { ($0.id, $0) })
    }

    var body: some View {
        let pages = manager.pageIDs
        let hidden = manager.orderedDescriptors.filter {
            $0.providesWidget && !manager.isEnabled($0.id) && manager.isUnlocked($0)
        }

            VStack(alignment: .leading, spacing: 18) {
                PresetGallery(manager: manager)

                Text("Glissez les widgets pour les réordonner ou les changer de page. Cliquez sur un widget pour changer sa taille. Astuce : un clic droit sur un widget dans l'encoche offre les mêmes options.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(pages.enumerated()), id: \.offset) { index, ids in
                    PageEditor(manager: manager, pageIndex: index, ids: ids, descriptors: descriptors)
                }

                NewPageDropZone(manager: manager, pageCount: pages.count)

                HiddenWidgetsSection(manager: manager, hidden: hidden)

                HStack {
                    Spacer()
                    Button("Réinitialiser la disposition") {
                        manager.resetLayout()
                    }
                }
            }
            .padding(20)
    }
}

// MARK: - Une page

private struct PageEditor: View {
    /// Dimensions réelles de la zone des widgets dans l'encoche dépliée.
    static let realWidth: CGFloat = NotchLayout.expandedSize.width - 36
    static let realHeight: CGFloat = 140

    let manager: ModuleManager
    let pageIndex: Int
    let ids: [String]
    let descriptors: [String: ModuleDescriptor]

    @State private var isTargeted = false

    var body: some View {
        let used = manager.usedCapacity(ofPage: ids)
        let capacity = NotchLayout.pageCapacity

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Page \(pageIndex + 1)")
                    .font(.headline)
                Spacer()
                Text("\(Double(used).formatted(.number.precision(.fractionLength(0...1)))) / \(Int(capacity)) de largeur")
                    .font(.caption)
                    .foregroundStyle(used > capacity ? .orange : .secondary)
                    .help(used > capacity ? "Page trop chargée : les widgets seront rétrécis. Réduisez une taille ou déplacez un widget." : "")
            }

            // Miniature fidèle de la page : les vrais widgets, à leur taille réelle, puis réduits.
            GeometryReader { proxy in
                let scale = max(0.1, (proxy.size.width - 16) / Self.realWidth)
                let spacing: CGFloat = 12
                // Mêmes colonnes que dans l'encoche : deux Mini consécutifs s'empilent.
                let columns = WidgetColumns.make(sizes: ids.map { manager.size(for: $0) })
                let columnWeights = columns.map { manager.weight(for: ids[$0[0]]) }
                let totalWeight = max(0.001, columnWeights.reduce(0, +))
                let available = Self.realWidth - spacing * CGFloat(max(0, columns.count - 1))

                HStack(spacing: spacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, column in
                        VStack(spacing: 8) {
                            ForEach(column, id: \.self) { index in
                                if let descriptor = descriptors[ids[index]] {
                                    WidgetTile(manager: manager, descriptor: descriptor, pageIndex: pageIndex, index: index)
                                        .environment(\.miniStacked, column.count == 2)
                                }
                            }
                        }
                        .frame(width: max(40, available * columnWeights[columnIndex] / totalWeight), height: Self.realHeight)
                    }
                }
                .frame(width: Self.realWidth, height: Self.realHeight, alignment: .leading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.realWidth * scale, height: Self.realHeight * scale, alignment: .topLeading)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
                }
            }
            .aspectRatio((Self.realWidth + 16) / (Self.realHeight + 16), contentMode: .fit)
            // Déposer sur l'espace libre de la page : le widget va en dernière position.
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first else { return false }
                place(id, page: pageIndex, index: ids.count)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }

    private func place(_ id: String, page: Int, index: Int) {
        withAnimation(.snappy) {
            if manager.isEnabled(id) {
                manager.move(id, toPage: page, index: index)
            } else {
                manager.enable(id, atPage: page, index: index)
            }
        }
    }
}

// MARK: - Un widget

private struct WidgetTile: View {
    let manager: ModuleManager
    let descriptor: ModuleDescriptor
    let pageIndex: Int
    let index: Int

    @State private var showsOptions = false
    @State private var dropSide: HorizontalEdge?

    var body: some View {
        let size = manager.size(for: descriptor.id)

        Group {
            if let module = manager.module(for: descriptor.id) {
                // Le vrai widget, en direct, non interactif (les clics servent à l'éditeur).
                Group {
                    if size == .mini { module.miniView() } else { module.expandedView() }
                }
                    .environment(\.widgetSize, size)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 4) {
                    ModuleIcon(symbol: descriptor.systemImage)
                        .font(.system(size: 22))
                        .frame(height: 24)
                    Text(descriptor.name)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(showsOptions ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Étiquette : nom et taille du widget.
        .overlay(alignment: .bottomLeading) {
            Text("\(String(localized: descriptor.name)) · \(String(localized: size.title))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .padding(6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: showsOptions ? 2 : 0)
        }
        // Indicateur d'insertion pendant un glisser-déposer.
        .overlay(alignment: dropSide == .leading ? .leading : .trailing) {
            if dropSide != nil {
                Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 4)
                    .offset(x: dropSide == .leading ? -6 : 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showsOptions = true }
        .help("Cliquez pour changer la taille, glissez pour déplacer")
        .draggable(descriptor.id) {
            Label { Text(descriptor.name) } icon: { ModuleIcon(symbol: descriptor.systemImage) }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, location in
            guard let id = items.first else { return false }
            // Moitié gauche : avant ce widget ; moitié droite : après.
            let target = location.x < tileWidth / 2 ? index : index + 1
            withAnimation(.snappy) {
                if manager.isEnabled(id) {
                    manager.move(id, toPage: pageIndex, index: target)
                } else {
                    manager.enable(id, atPage: pageIndex, index: target)
                }
            }
            dropSide = nil
            return true
        } isTargeted: { targeted in
            dropSide = targeted ? .trailing : nil
        }
        .background(GeometryReader { proxy in Color.clear.onAppear { tileWidth = proxy.size.width } })
        .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Label { Text(descriptor.name) } icon: { ModuleIcon(symbol: descriptor.systemImage) }
                    .font(.headline)
                Picker("Taille", selection: Binding(
                    get: { manager.size(for: descriptor.id) },
                    set: { newSize in withAnimation(.snappy) { manager.setSize(newSize, for: descriptor.id) } }
                )) {
                    ForEach(WidgetSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Largeur naturelle : les libellés (plus longs en anglais) ne débordent jamais.
                .fixedSize()
                Button("Masquer ce widget", role: .destructive) {
                    showsOptions = false
                    withAnimation(.snappy) { manager.setEnabled(false, for: descriptor.id) }
                }
            }
            .padding(16)
            .fixedSize()
        }
    }

    @State private var tileWidth: CGFloat = 80
}

// MARK: - Nouvelle page

private struct NewPageDropZone: View {
    let manager: ModuleManager
    let pageCount: Int
    @State private var isTargeted = false

    var body: some View {
        Label("Déposez un widget ici pour créer une nouvelle page", systemImage: "plus.rectangle.on.rectangle")
            .font(.callout)
            .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary.opacity(0.5))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first else { return false }
                withAnimation(.snappy) {
                    if manager.isEnabled(id) {
                        manager.move(id, toPage: pageCount, index: 0)
                    } else {
                        manager.enable(id, atPage: pageCount, index: 0)
                    }
                }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Widgets masqués

private struct HiddenWidgetsSection: View {
    let manager: ModuleManager
    let hidden: [ModuleDescriptor]
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Widgets masqués")
                .font(.headline)
            HStack(spacing: 8) {
                if hidden.isEmpty {
                    Text("Glissez un widget ici pour le masquer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(hidden) { descriptor in
                        Label { Text(descriptor.name) } icon: { ModuleIcon(symbol: descriptor.systemImage) }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                            .draggable(descriptor.id)
                            .help("Glissez dans une page pour l'afficher")
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first, manager.isEnabled(id) else { return false }
                withAnimation(.snappy) { manager.setEnabled(false, for: id) }
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

// MARK: - Dispositions prêtes à l'emploi

private struct PresetGallery: View {
    let manager: ModuleManager
    @State private var pending: LayoutPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dispositions prêtes à l'emploi")
                    .font(.headline)
                Spacer()
                if manager.settingsBeforePreset != nil {
                    Button("Annuler la dernière disposition") { withAnimation(.snappy) { manager.undoPreset() } }
                        .buttonStyle(.link)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(LayoutPreset.all) { preset in
                        Button { pending = preset } label: {
                            PresetCard(preset: preset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
        .confirmationDialog(
            pending.map { String(localized: "Appliquer la disposition « \(String(localized: $0.name)) » ?") } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Appliquer") {
                if let preset = pending { withAnimation(.snappy) { manager.apply(preset) } }
                pending = nil
            }
            Button("Annuler", role: .cancel) { pending = nil }
        } message: {
            Text("Les modules affichés, leurs pages et leurs tailles seront remplacés. Vous pourrez revenir en arrière.")
        }
    }
}

/// Carte d'une disposition : schéma des pages (rectangles proportionnels aux tailles) et nom.
private struct PresetCard: View {
    let preset: LayoutPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 3) {
                ForEach(Array(preset.pages.prefix(3).enumerated()), id: \.offset) { _, page in
                    HStack(spacing: 2) {
                        ForEach(page, id: \.self) { id in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.35))
                                .frame(width: 26 * (preset.sizes[id] ?? .small).weight, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(6)
            .frame(width: 150, height: 52, alignment: .topLeading)
            .background(.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Label(String(localized: preset.name), systemImage: preset.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(preset.summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 150, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
