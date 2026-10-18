import SwiftUI
import Observation

/// Module Agents : une page entière où la mascotte suit le travail des agents IA (Claude Code pour
/// commencer). L'encoche s'ouvre d'elle-même sur cette page quand un agent attend une réponse.
@MainActor
@Observable
final class AgentsModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "agents",
        name: "Agents",
        summary: "Vos agents IA sur une page entière : la mascotte suit leur travail et l'encoche s'ouvre quand l'un d'eux attend votre réponse.",
        systemImage: "sparkles.rectangle.stack",
        category: .productivity,
        tier: .free,
        defaultEnabled: false,
        fullPage: true
    )

    /// Durée pendant laquelle la mascotte se réjouit après la fin d'une tâche.
    static let celebrationDuration: TimeInterval = 6

    @ObservationIgnored let context: ModuleContext
    /// Sessions qui attendaient déjà une réponse (pour n'ouvrir l'encoche qu'aux nouvelles demandes).
    @ObservationIgnored private var knownWaiting: Set<String> = []
    @ObservationIgnored private var knownWorking: Set<String> = []
    @ObservationIgnored private var isRunning = false
    /// Fin de la petite fête après une tâche terminée.
    private(set) var celebrateUntil: Date?

    /// Discussion avec la mascotte (Apple Intelligence ou Claude).
    @ObservationIgnored private(set) var chat: MascotChat!
    /// Services suivis (Vercel, Stripe ; GitHub vient de son module).
    let services = AgentServices()

    /// Module GitHub, s'il est actif.
    var github: GitHubModule? { context.otherModule("github") as? GitHubModule }

    init(context: ModuleContext) {
        self.context = context
        chat = MascotChat(
            persona: { [weak self] in self?.persona ?? "" },
            agentsSummary: { [weak self] in self?.statusSummary ?? "" }
        )
    }

    /// Consignes données à Apple Intelligence : la mascotte, son ton, ses limites.
    var persona: String {
        """
        Tu es \(mascot.name), la petite mascotte de Notchkit qui vit dans l'encoche du Mac. \
        Tu es gentille, enjouée et brève : deux ou trois phrases au plus, sans listes ni Markdown, \
        car tes réponses s'affichent dans un tout petit espace. Réponds dans la langue de l'utilisateur. \
        Pour parler du travail des agents de code (Claude Code), utilise l'outil etatDesAgents. \
        Si une question demande un long raisonnement ou du code, suggère de passer à Claude.
        """
    }

    /// État des agents en quelques lignes (pour l'outil d'Apple Intelligence).
    var statusSummary: String {
        let sessions = sessions
        guard !sessions.isEmpty else { return "Aucun agent de code n'est actif en ce moment." }
        return sessions.prefix(5).map { session in
            let state = switch session.state {
            case .working: "au travail"
            case .waitingForPermission: "attend l'accord de l'utilisateur"
            case .awaitingReply, .finished: "a terminé"
            }
            var line = "Projet \(session.projectName ?? "sans nom") (Claude Code) : \(state)"
            if let prompt = session.prompt { line += ". Demande : \(prompt)" }
            if let action = session.currentAction { line += ". Action en cours : \(action.text)" }
            return line
        }.joined(separator: "\n")
    }

    /// Module Claude Code, s'il est actif (il reçoit les événements des hooks).
    var claude: ClaudeModule? { context.otherModule(ClaudeModule.descriptor.id) as? ClaudeModule }

    /// Sessions connues, de la plus récente à la plus ancienne.
    var sessions: [ClaudeSession] {
        #if DEBUG
        if let previewSessions { return previewSessions }
        #endif
        return (claude?.tracker.sessions.values.map { $0 } ?? []).sorted { $0.lastEventAt > $1.lastEventAt }
    }

    #if DEBUG
    /// Sessions imposées pour les captures de développement.
    var previewSessions: [ClaudeSession]?
    #endif

    var mascot: MascotDesign { context.mascot() }

    func start() {
        isRunning = true
        observeSessions()
        // Nouveau paiement : petite fête de la mascotte.
        services.onNewCharge = { [weak self] in
            self?.celebrateUntil = Date().addingTimeInterval(Self.celebrationDuration)
        }
        services.start()
    }

    func stop() {
        isRunning = false
        services.stop()
    }

    /// Suit les sessions : nouvelle demande d'accord → l'encoche s'ouvre ; tâche finie → fête.
    private func observeSessions() {
        trackChanges(of: { [weak self] in
            guard let self, self.isRunning else { return }
            _ = self.claude?.tracker.sessions
        }, perform: { [weak self] in
            self?.sessionsChanged()
        })
        sessionsChanged()
    }

    private func sessionsChanged() {
        guard isRunning else { return }
        let sessions = sessions
        let waiting = Set(sessions.filter { $0.state == .waitingForPermission }.map(\.id))
        let working = Set(sessions.filter { $0.state == .working }.map(\.id))
        if !waiting.subtracting(knownWaiting).isEmpty {
            context.showModule()
        }
        // Une session qui travaillait vient de s'arrêter (terminée ou en attente d'une suite).
        let stopped = knownWorking.subtracting(working).subtracting(waiting)
        if sessions.contains(where: { stopped.contains($0.id) && ($0.state == .finished || $0.state == .awaitingReply) }) {
            celebrateUntil = Date().addingTimeInterval(Self.celebrationDuration)
        }
        knownWaiting = waiting
        knownWorking = working
    }

    /// Humeur de la mascotte pour une session (ou sans session).
    nonisolated static func mood(for session: ClaudeSession?, celebrating: Bool) -> MascotMood {
        if session?.state == .waitingForPermission { return .waiting }
        if session?.state == .working { return .working }
        return celebrating ? .happy : .idle
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 4 }

    func miniView() -> AnyView {
        AnyView(LiveMascotView(design: mascot, mood: Self.mood(for: sessions.first, celebrating: false), size: 40))
    }

    func expandedView() -> AnyView {
        AnyView(AgentsHomeView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(AgentsSettingsView(chat: chat, services: services))
    }

    /// Garde l'encoche ouverte pendant la saisie d'un message.
    func holdExpanded(_ hold: Bool) {
        context.holdExpanded(hold)
    }
}
