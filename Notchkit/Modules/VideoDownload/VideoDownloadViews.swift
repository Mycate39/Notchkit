import SwiftUI

struct VideoDownloadExpandedView: View {
    let module: VideoDownloadModule
    @State private var link = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !module.isToolInstalled {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.circle")
                        .font(.system(size: 22))
                    Text("yt-dlp n'est pas installé.")
                        .font(.system(size: 11, weight: .medium))
                    Button("Installer…") { module.openSettings() }
                        .controlSize(.small)
                    Text("Réglages > Modules > Vidéos")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                linkField
                formatRow
                if module.downloads.isEmpty {
                    Text("Collez un lien de vidéo puis appuyez sur Entrée.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(module.downloads) { download in
                                DownloadRow(module: module, download: download)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .padding(10)
        .onChange(of: isTyping) { _, typing in module.holdExpanded(typing) }
        .onAppear { module.refreshToolStatus() }
    }

    private var linkField: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            TextField("Coller un lien de vidéo", text: $link)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isTyping)
                .onSubmit(start)
            Button(action: start) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(YTDLP.isValidLink(link) ? .red : .white.opacity(0.3))
            }
            .buttonStyle(.notch)
            .disabled(!YTDLP.isValidLink(link))
            .help("Télécharger")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(StandBy.surface, in: Capsule())
    }

    private var formatRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(YTDLP.Format.allCases) { format in
                    Button {
                        module.format = format
                    } label: {
                        Text(format.title)
                    }
                    .disabled(format.requiresFFmpeg && !module.hasFFmpeg)
                }
            } label: {
                Label(String(localized: module.format.title), systemImage: module.format.isAudio ? "music.note" : "film")
                    .font(.system(size: 9, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button { module.chooseDirectory() } label: {
                Label(module.directory.lastPathComponent, systemImage: "folder")
            }
            .buttonStyle(.standBy(.small))
            .help("Dossier de destination : \(module.directory.path)")
        }
    }

    private func start() {
        guard YTDLP.isValidLink(link) else { return }
        module.download(link)
        link = ""
        isTyping = false
    }
}

private struct DownloadRow: View {
    let module: VideoDownloadModule
    let download: VideoDownload

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                Circle().trim(from: 0, to: download.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: download.progress)
                Image(systemName: download.format.isAudio ? "music.note" : "film")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(download.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundStyle(isError ? .red : .white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if download.isRunning {
                Button { module.cancel(download.id) } label: { Image(systemName: "xmark") }
                    .help("Annuler")
            } else {
                Button { module.reveal(download) } label: { Image(systemName: "magnifyingglass") }
                    .help("Afficher dans le Finder")
                Button { module.remove(download.id) } label: { Image(systemName: "trash") }
                    .help("Retirer de la liste")
            }
        }
        .buttonStyle(.standBy(.small, circle: true))
    }

    private var tint: Color {
        switch download.state {
        case .finished: .green
        case .failed, .cancelled: .gray
        case .running: .red
        }
    }

    private var isError: Bool {
        if case .failed = download.state { return true }
        return false
    }

    private var subtitle: String {
        switch download.state {
        case .running:
            let percent = download.progress.formatted(.percent.precision(.fractionLength(0)))
            return download.detail.isEmpty ? percent : "\(percent) · \(download.detail)"
        case .finished: return String(localized: "Terminé")
        case let .failed(message): return message
        case .cancelled: return String(localized: "Annulé")
        }
    }
}

// MARK: - Réglages

struct VideoDownloadSettingsView: View {
    @Bindable var module: VideoDownloadModule
    @State private var confirmInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(module.isToolInstalled ? "yt-dlp installé" : "yt-dlp non installé",
                      systemImage: module.isToolInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(module.isToolInstalled ? .green : .orange)
                Label(module.hasFFmpeg ? "ffmpeg installé" : "ffmpeg absent (qualité limitée, pas de MP3)",
                      systemImage: module.hasFFmpeg ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(module.hasFFmpeg ? .green : .secondary)
            }
            .font(.caption)

            if !module.isToolInstalled {
                Button(module.isInstalling ? "Installation…" : "Installer yt-dlp…") { confirmInstall = true }
                    .disabled(module.isInstalling)
            }
            if !module.hasFFmpeg {
                Text("ffmpeg (facultatif : meilleure qualité, MP3) s'installe dans le Terminal avec « brew install ffmpeg ». Sur un Mac Intel, Homebrew peut devoir le compiler, ce qui est long.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let log = module.installLog {
                Text(log).font(.caption).foregroundStyle(.secondary)
            }

            LabeledContent("Dossier de destination") {
                Button(module.directory.path) { module.chooseDirectory() }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Respectez les droits d'auteur : les conditions d'utilisation de YouTube interdisent de télécharger des vidéos sans autorisation. Réservez ce module à vos propres vidéos, aux contenus sous licence libre ou téléchargés avec l'accord de leurs auteurs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Installer yt-dlp ?", isPresented: $confirmInstall) {
            Button("Télécharger et installer") { module.installTool() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Notchkit va télécharger le programme officiel yt-dlp pour macOS depuis GitHub (logiciel libre, environ 35 Mo), vérifier son empreinte, puis l'installer dans son dossier. Rien n'est modifié ailleurs sur votre Mac.")
        }
        .onAppear { module.refreshToolStatus() }
    }
}
