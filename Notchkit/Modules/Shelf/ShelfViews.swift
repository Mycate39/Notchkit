import SwiftUI
import UniformTypeIdentifiers

// MARK: - Carte dans l'encoche dépliée

struct ShelfExpandedView: View {
    let module: ShelfModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if module.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22))
                    Text("Glissez des fichiers sur l'encoche pour les garder ici.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(module.items) { item in
                            ShelfItemView(module: module, item: item, compact: size == .small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Étagère")
                .font(.system(size: 12, weight: .semibold))
            if !module.items.isEmpty {
                Text("\(module.items.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if module.isWorking {
                ProgressView().controlSize(.mini)
            }
            if !module.items.isEmpty {
                Menu {
                    Button("Tout compresser (ZIP)") { module.zip(module.items) }
                    if module.isICloudAvailable {
                        Button("Tout copier vers iCloud Drive") { module.copyToICloud(module.items) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Actions")
                Button { module.airDrop(module.items) } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                .help("Tout envoyer par AirDrop")
                Button { module.clear() } label: {
                    Image(systemName: "trash")
                }
                .help("Vider l'étagère")
            }
        }
        .buttonStyle(.standBy(.small, circle: true))
    }
}

/// Un fichier de l'étagère : aperçu et nom ; à glisser vers une autre app pour le récupérer.
private struct ShelfItemView: View {
    let module: ShelfModule
    let item: ShelfItem
    let compact: Bool

    var body: some View {
        let url = item.resolvedURL()

        VStack(spacing: 3) {
            Group {
                if let url {
                    Image(nsImage: module.thumbnails.image(for: url))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: compact ? 34 : 44, height: compact ? 34 : 44)

            Text(item.name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .foregroundStyle(url == nil ? .white.opacity(0.4) : .white.opacity(0.85))
        }
        .frame(width: compact ? 52 : 64)
        .padding(4)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help(url == nil ? "Fichier introuvable (déplacé ou supprimé)" : "Glissez pour récupérer le fichier · double-clic pour l'ouvrir")
        .onTapGesture(count: 2) { module.open(item) }
        // Glisser vers le Finder ou une autre app : le fichier y est copié.
        .onDrag {
            guard let url else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Ouvrir") { module.open(item) }.disabled(url == nil)
            Button("Afficher dans le Finder") { module.reveal(item) }.disabled(url == nil)
            Button("Envoyer par AirDrop") { module.airDrop([item]) }.disabled(url == nil)
            Button("Copier") { module.copy([item]) }.disabled(url == nil)
            Divider()
            Button("Compresser (ZIP)") { module.zip([item]) }.disabled(url == nil)
            if let url, FileActions.isImage(url) {
                Menu("Convertir en") {
                    ForEach(FileActions.ImageFormat.allCases, id: \.self) { format in
                        Button(format.rawValue.uppercased()) { module.convertImage(item, to: format) }
                    }
                }
            }
            if let url, FileActions.isVideo(url) {
                Button("Convertir en MP4") { module.convertVideo(item) }
            }
            if module.isICloudAvailable {
                Button("Copier vers iCloud Drive") { module.copyToICloud([item]) }.disabled(url == nil)
            }
            Divider()
            Button("Retirer de l'étagère") { module.remove(item) }
        }
    }
}

// MARK: - Zones de dépôt (fichiers glissés sur l'encoche)

/// Affichées à la place des widgets quand on glisse des fichiers sur l'encoche.
struct DropZonesView: View {
    let hovered: DropZone?
    let shelfAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            if shelfAvailable {
                zone(.shelf, title: "Garder dans l'étagère", symbol: "tray.and.arrow.down.fill", color: .green)
            }
            zone(.airDrop, title: "Envoyer par AirDrop", symbol: "dot.radiowaves.left.and.right", color: .blue)
        }
    }

    private func zone(_ zone: DropZone, title: LocalizedStringKey, symbol: String, color: Color) -> some View {
        let isHovered = hovered == zone

        return VStack(spacing: 8) {
            ZStack {
                if zone == .airDrop { AirDropWaves(isActive: isHovered, color: color) }
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isHovered ? color : .white.opacity(0.8))
                    .symbolEffect(.bounce, value: isHovered)
            }
            .frame(height: 54)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? .white : .white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? color.opacity(0.22) : .white.opacity(0.06))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isHovered ? color : .white.opacity(0.25))
        }
        .scaleEffect(isHovered ? 1.02 : 1)
    }
}

/// Ondes concentriques qui s'élargissent (évoque AirDrop) pendant le survol de la zone.
private struct AirDropWaves: View {
    let isActive: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { index in
                    let phase = (time / 1.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(isActive ? (1 - phase) * 0.8 : 0), lineWidth: 2)
                        .frame(width: 24 + phase * 50, height: 24 + phase * 50)
                }
            }
        }
    }
}

// MARK: - Réglages

struct ShelfSettingsView: View {
    @Bindable var module: ShelfModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Afficher le nombre de fichiers quand l'encoche est repliée", isOn: $module.showInCompact)
            Text("Faites glisser des fichiers sur l'encoche : à gauche pour les garder ici, à droite pour les envoyer par AirDrop. Les fichiers ne sont ni copiés ni déplacés, l'étagère garde seulement un lien vers eux.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !module.items.isEmpty {
                Button("Vider l'étagère (\(module.items.count))", role: .destructive, action: module.clear)
            }
        }
    }
}
