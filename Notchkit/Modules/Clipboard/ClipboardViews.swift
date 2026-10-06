import SwiftUI

struct ClipboardExpandedView: View {
    let module: ClipboardModule
    @Environment(\.widgetSize) private var size
    @State private var search = ""
    @FocusState private var isSearching: Bool

    private var filtered: [ClipboardItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return module.items }
        return module.items.filter { $0.preview.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Rechercher", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .focused($isSearching)
                if !module.items.isEmpty {
                    Button { module.clearUnpinned() } label: { Image(systemName: "trash") }
                        .buttonStyle(.notch)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Effacer l'historique (sauf les éléments épinglés)")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(StandBy.surface, in: Capsule())

            if filtered.isEmpty {
                Text(module.items.isEmpty ? "Copiez du texte, une image ou des fichiers : ils apparaîtront ici." : "Aucun résultat")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(filtered) { item in
                            ClipboardRow(module: module, item: item)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        // Pendant la recherche, l'encoche reste ouverte.
        .onChange(of: isSearching) { _, searching in module.holdExpanded(searching) }
    }
}

private struct ClipboardRow: View {
    let module: ClipboardModule
    let item: ClipboardItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            // Vignette carrée : une image est recadrée au centre, comme les icônes des autres lignes.
            thumbnail
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.preview)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned || isHovered {
                Button { module.togglePin(item) } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.notch)
                .font(.system(size: 9))
                .foregroundStyle(item.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.6)))
                .help(item.isPinned ? "Désépingler" : "Épingler")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { module.copy(item) }
        .help("Cliquer pour copier")
        .contextMenu {
            Button("Copier") { module.copy(item) }
            Button(item.isPinned ? "Désépingler" : "Épingler") { module.togglePin(item) }
            Divider()
            Button("Supprimer") { module.remove(item) }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        case let .image(data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        case let .files(urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable()
        }
    }

    private var subtitle: String {
        let time = item.copiedAt.formatted(.relative(presentation: .named))
        return [item.sourceApp, time].compactMap { $0 }.joined(separator: " · ")
    }
}

struct ClipboardSettingsView: View {
    @Bindable var module: ClipboardModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Conserver l'historique après le redémarrage de l'app", isOn: $module.keepHistory)
            if let status = module.accessStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Les contenus marqués confidentiels (mots de passe copiés depuis un gestionnaire) ne sont jamais enregistrés. L'historique reste sur ce Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !module.items.isEmpty {
                Button("Effacer l'historique", role: .destructive, action: module.clearUnpinned)
            }
        }
    }
}
