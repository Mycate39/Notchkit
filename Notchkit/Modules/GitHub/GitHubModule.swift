import AppKit
import SwiftUI
import Observation

/// Module GitHub : vos pull requests ouvertes et l'état de leurs vérifications, plus celles à relire.
/// Jeton d'accès personnel (gratuit) dans le trousseau ; rafraîchi toutes les 3 minutes.
@MainActor
@Observable
final class GitHubModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "github",
        name: "GitHub",
        summary: "Vos pull requests et l'état de leurs vérifications, en direct.",
        systemImage: "point.3.connected.trianglepath.dotted",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    static let refreshInterval: TimeInterval = 180

    private(set) var hasToken = GitHubToken.read() != nil
    private(set) var mine: [PullRequest] = []
    private(set) var toReview: [PullRequest] = []
    private(set) var errorMessage: String?
    private(set) var lastUpdate: Date?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard loop == nil, !AutomatedRun.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, GitHubToken.save(trimmed) else { return }
        hasToken = true
        Task { await refresh() }
    }

    func removeToken() {
        GitHubToken.delete()
        hasToken = false
        mine = []
        toReview = []
    }

    func refresh() async {
        guard let token = GitHubToken.read() else { hasToken = false; return }
        let client = GitHubClient(token: token)
        do {
            var mine = try await client.search("author:@me")
            for index in mine.indices {
                mine[index].checks = (try? await client.checks(for: mine[index])) ?? .none
            }
            let review = try await client.search("review-requested:@me")
            // Une vérification qui vient d'échouer : petite alerte dans l'encoche.
            let failedNow = mine.filter { pull in
                pull.checks == .failure && self.mine.first(where: { $0.id == pull.id })?.checks == .pending
            }
            withAnimation(.snappy) {
                self.mine = mine
                self.toReview = review
            }
            errorMessage = nil
            lastUpdate = Date()
            if let failed = failedNow.first { context.presentAlert(GitHubAlerts.checksFailed(failed)) }
        } catch GitHubClient.Failure.unauthorized {
            errorMessage = String(localized: "Jeton refusé par GitHub. Vérifiez-le dans les réglages.")
        } catch {
            errorMessage = String(localized: "GitHub est injoignable pour le moment.")
        }
    }

    func open(_ pull: PullRequest) {
        NSWorkspace.shared.open(pull.url)
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "point.3.connected.trianglepath.dotted", value: hasToken ? "\(mine.count)" : nil,
                           caption: String(localized: "Pull requests")))
    }

    func expandedView() -> AnyView { AnyView(GitHubExpandedView(module: self)) }
    func settingsView() -> AnyView? { AnyView(GitHubSettingsView(module: self)) }
}

enum GitHubAlerts {
    @MainActor
    static func checksFailed(_ pull: PullRequest) -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)),
            trailing: AnyView(Text("#\(pull.number) échoue").foregroundStyle(.red).minimumScaleFactor(0.7)),
            duration: .seconds(5)
        )
    }
}

struct GitHubExpandedView: View {
    let module: GitHubModule

    var body: some View {
        Group {
            if !module.hasToken {
                VStack(spacing: 6) {
                    Image(systemName: "key").font(.system(size: 20))
                    Text("Ajoutez un jeton d'accès personnel GitHub dans les réglages du module.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Mes pull requests").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if !module.toReview.isEmpty {
                            Label("\(module.toReview.count) à relire", systemImage: "eye")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    if let error = module.errorMessage {
                        Text(error).font(.system(size: 10)).foregroundStyle(.red)
                    }
                    if module.mine.isEmpty && module.errorMessage == nil {
                        Text("Aucune pull request ouverte.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(module.mine + module.toReview) { pull in
                                    PullRequestRow(pull: pull, isReview: module.toReview.contains(pull))
                                        .onTapGesture { module.open(pull) }
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                }
            }
        }
        .padding(10)
    }
}

private struct PullRequestRow: View {
    let pull: PullRequest
    let isReview: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(pull.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text("\(pull.repository) #\(pull.number)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .help("Ouvrir sur GitHub")
    }

    private var symbol: String {
        if isReview { return "eye" }
        switch pull.checks {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .none: return pull.isDraft ? "pencil.circle" : "circle"
        }
    }

    private var color: Color {
        if isReview { return StandBy.amber }
        switch pull.checks {
        case .success: return .green
        case .failure: return .red
        case .pending: return .orange
        case .none: return .white.opacity(0.5)
        }
    }
}

struct GitHubSettingsView: View {
    @Bindable var module: GitHubModule
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if module.hasToken {
                Label("Jeton enregistré dans le trousseau", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Retirer le jeton", role: .destructive, action: module.removeToken)
            } else {
                SecureField("Jeton d'accès personnel", text: $token)
                Button("Enregistrer") {
                    module.saveToken(token)
                    token = ""
                }
                .disabled(token.isEmpty)
            }
            Text("Créez un jeton gratuit sur GitHub (Settings › Developer settings › Personal access tokens), avec l'accès en lecture aux dépôts. Il est gardé dans le trousseau de macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Créer un jeton sur GitHub", destination: URL(string: "https://github.com/settings/tokens?type=beta")!)
                .font(.caption)
        }
    }
}
