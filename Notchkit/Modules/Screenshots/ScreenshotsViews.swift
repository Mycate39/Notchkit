import SwiftUI

// MARK: - Carte dans l'encoche dépliée

struct ScreenshotsExpandedView: View {
    let module: ScreenshotsModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if module.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22))
                    Text("Les captures d'écran faites depuis l'ouverture de votre session apparaîtront ici.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Encoche basse : vignettes plus petites, puis sans l'heure, plutôt que coupées.
                ViewThatFits(in: .vertical) {
                    strip(compact: size == .small, showsTime: true)
                    strip(compact: true, showsTime: true)
                    strip(compact: true, showsTime: false)
                }
            }
        }
        .padding(10)
    }

    private func strip(compact: Bool, showsTime: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(module.items) { item in
                    ScreenshotItemView(module: module, item: item, compact: compact, showsTime: showsTime)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Captures d'écran")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if !module.items.isEmpty {
                Text("\(module.items.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if !module.items.isEmpty {
                Button { module.airDrop(module.items) } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                .help("Tout envoyer par AirDrop")
                .accessibilityLabel(Text("Tout envoyer par AirDrop"))
                Button { module.reveal(module.items) } label: {
                    Image(systemName: "folder")
                }
                .help("Afficher dans le Finder")
                .accessibilityLabel(Text("Afficher dans le Finder"))
            }
        }
        .buttonStyle(.standBy(.small, circle: true))
    }
}

/// Une capture : aperçu (badge lecture pour une vidéo) et heure ; à glisser vers une autre app.
private struct ScreenshotItemView: View {
    let module: ScreenshotsModule
    let item: Screenshot
    let compact: Bool
    var showsTime = true

    var body: some View {
        VStack(spacing: 3) {
            ScreenshotThumbnail(item: item, module: module,
                                size: compact ? CGSize(width: 54, height: 36) : CGSize(width: 72, height: 46))
            if showsTime {
                Text(item.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(4)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help("Glissez pour récupérer le fichier · double-clic pour l'ouvrir")
        .onTapGesture(count: 2) { module.open(item) }
        // Glisser vers le Finder, un message ou un document : le fichier y est copié.
        .onDrag { NSItemProvider.file(at: item.url) }
        .contextMenu {
            Button("Ouvrir") { module.open(item) }
            Button("Afficher dans le Finder") { module.reveal([item]) }
            Button("Envoyer par AirDrop") { module.airDrop([item]) }
            Button("Copier") { module.copy(item) }
            Divider()
            Button("Placer dans la corbeille", role: .destructive) { module.moveToTrash(item) }
        }
    }
}

/// Aperçu d'une capture, recadré, avec un badge « lecture » pour les enregistrements.
struct ScreenshotThumbnail: View {
    let item: Screenshot
    let module: ScreenshotsModule
    let size: CGSize

    var body: some View {
        Image(nsImage: module.thumbnails.image(for: item.url))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: min(6, size.height / 4), style: .continuous))
            .overlay {
                if item.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: size.height * 0.32))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
    }
}

// MARK: - Réglages

struct ScreenshotsSettingsView: View {
    @Bindable var module: ScreenshotsModule

    var body: some View {
        Group {
            Toggle("Afficher une alerte à chaque nouvelle capture", isOn: $module.alertOnCapture)
            Text("Notchkit liste les captures et enregistrements d'écran faits depuis le démarrage du Mac ou l'ouverture de votre session, où qu'ils soient enregistrés. S'ils sont sur le Bureau, macOS demandera une fois l'accès à ce dossier pour afficher les aperçus.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
