import AppKit
import SwiftUI
import Observation

/// Module Git : branche, avance/retard et fichiers modifiés du projet ouvert dans Xcode ou le Terminal
/// (ou de dossiers ajoutés), avec fetch et pull rapides. Utilise l'outil `git` du Mac.
@MainActor
@Observable
final class GitModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "git",
        name: "Git",
        summary: "Branche et fichiers modifiés du projet ouvert dans Xcode ou le Terminal, avec fetch et pull.",
        systemImage: "arrow.triangle.branch",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    /// Dépôt affiché et son état.
    private(set) var repository: URL?
    private(set) var status: GitStatus?
    private(set) var isBusy = false
    private(set) var lastError: String?
    /// Dépôt détecté automatiquement (Xcode ou Terminal), distinct des dossiers ajoutés.
    private(set) var detected: URL?

    /// Dossiers ajoutés par l'utilisateur (chemins).
    var folders: [String] {
        didSet { UserDefaults.standard.set(folders, forKey: Keys.folders) }
    }

    private enum Keys {
        static let folders = "module.git.folders"
    }

    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(context: ModuleContext) {
        folders = UserDefaults.standard.stringArray(forKey: Keys.folders) ?? []
    }

    /// Tous les dépôts connus : détecté d'abord, puis les dossiers ajoutés.
    var repositories: [URL] {
        var list = detected.map { [$0] } ?? []
        for path in folders where !list.contains(where: { $0.path == path }) {
            list.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        return list
    }

    func start() {
        if repository == nil { repository = repositories.first }
        guard !AutomatedRun.isActive else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { self?.detect(in: app) } }
        }
        if let app = NSWorkspace.shared.frontmostApplication { detect(in: app) }
    }

    func stop() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func detect(in app: NSRunningApplication) {
        guard let folder = ProjectDetector.folder(for: app) else { return }
        Task {
            guard let root = await GitCommand.repositoryRoot(containing: folder), root != detected else { return }
            detected = root
            select(root)
        }
    }

    func select(_ url: URL) {
        repository = url
        status = nil
        refresh()
    }

    func refresh() {
        guard let repository else { return }
        Task {
            let output = await GitCommand.run(["status", "--porcelain=v2", "--branch"], in: repository)
            if self.repository == repository { status = output.map(GitStatus.parse) }
        }
    }

    func fetch() { runAction(["fetch", "--quiet"]) }
    func pull() { runAction(["pull", "--ff-only", "--quiet"]) }

    private func runAction(_ arguments: [String]) {
        guard let repository, !isBusy else { return }
        isBusy = true
        lastError = nil
        Task {
            let output = await GitCommand.run(arguments, in: repository)
            isBusy = false
            if output == nil { lastError = String(localized: "Échec de la commande git (connexion, droits ou conflits).") }
            refresh()
        }
    }

    func openInTerminal() {
        guard let repository,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProjectDetector.terminalID)
        else { return }
        NSWorkspace.shared.open([repository], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        folders += panel.urls.map(\.path).filter { !folders.contains($0) }
        if repository == nil { repository = repositories.first; refresh() }
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "arrow.triangle.branch", value: status.map { "\($0.changes.count)" },
                           caption: status?.branch ?? String(localized: "Git")))
    }

    func expandedView() -> AnyView { AnyView(GitExpandedView(module: self)) }
    func settingsView() -> AnyView? { AnyView(GitSettingsView(module: self)) }
}

struct GitExpandedView: View {
    let module: GitModule

    var body: some View {
        Group {
            if let repository = module.repository {
                content(repository)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 22))
                    Text("Ouvrez un projet dans Xcode ou le Terminal, ou ajoutez un dossier dans les réglages.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .onAppear { module.refresh() }
        .task(id: module.repository) {
            // Rafraîchi toutes les 10 s tant que la carte est affichée.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                module.refresh()
            }
        }
    }

    private func content(_ repository: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(module.repositories, id: \.path) { url in
                        Button(url.lastPathComponent) { module.select(url) }
                    }
                } label: {
                    Text(repository.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if let status = module.status {
                    Label(status.branch, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    if status.ahead > 0 { Text("↑\(status.ahead)").font(.system(size: 10, weight: .bold)) }
                    if status.behind > 0 { Text("↓\(status.behind)").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange) }
                }
                Spacer()
                Button(action: module.fetch) { Image(systemName: "arrow.clockwise") }
                    .help("Fetch")
                Button(action: module.pull) { Image(systemName: "arrow.down.to.line") }
                    .help("Pull (avance rapide uniquement)")
                    .disabled(module.status?.behind == 0)
                Button(action: module.openInTerminal) { Image(systemName: "terminal") }
                    .help("Ouvrir dans le Terminal")
            }
            .buttonStyle(.standBy(.small, circle: true))
            .disabled(module.isBusy)

            if let error = module.lastError {
                Text(error).font(.system(size: 9)).foregroundStyle(.red).lineLimit(1)
            }
            if let status = module.status {
                if status.isClean {
                    Label("Aucune modification", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(status.changes) { change in
                                HStack(spacing: 6) {
                                    Text(GitExpandedView.letter(change.kind))
                                        .font(.system(size: 9, weight: .bold).monospaced())
                                        .foregroundStyle(GitExpandedView.color(change.kind))
                                        .frame(width: 10)
                                    Text(change.path)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    static func letter(_ kind: GitStatus.Change.Kind) -> String {
        switch kind {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "?"
        case .conflict: "U"
        }
    }

    static func color(_ kind: GitStatus.Change.Kind) -> Color {
        switch kind {
        case .modified, .renamed: .orange
        case .added, .untracked: .green
        case .deleted, .conflict: .red
        }
    }
}

struct GitSettingsView: View {
    @Bindable var module: GitModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Le projet ouvert dans Xcode ou dans le Terminal est détecté automatiquement. Ajoutez ici d'autres dossiers à suivre.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(module.folders, id: \.self) { path in
                HStack {
                    Image(systemName: "folder")
                    Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Retirer") { module.removeFolder(path) }.buttonStyle(.link)
                }
            }
            Button("Ajouter un dossier…", action: module.addFolder)
        }
    }
}

#if DEBUG
extension GitModule {
    /// État fictif pour les images de démonstration.
    func debugSet(repository: URL, status: GitStatus) {
        self.repository = repository
        self.status = status
    }
}
#endif
