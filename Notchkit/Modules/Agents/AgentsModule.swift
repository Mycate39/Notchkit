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
        summary: "Claude Code sur une page entière : la mascotte suit son travail, son activité s'affiche dans l'encoche repliée et l'encoche s'ouvre quand il attend votre réponse.",
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



    init(context: ModuleContext) {
        self.context = context
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
    }

    func stop() {
        isRunning = false
    }

    /// Suit les sessions : nouvelle demande d'accord → son de la mascotte (l'encoche ne s'ouvre plus d'elle-même :
    /// on répond depuis la bulle cerclée d'ambre, ou en cliquant dessus) ; tâche finie → fête.
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
            MascotSounds.shared.play(.question)
        } else if !working.subtracting(knownWorking).subtracting(knownWaiting).isEmpty {
            // Un agent se met au travail (pas une simple reprise après un accord).
            MascotSounds.shared.play(.start)
        }
        // Une session qui travaillait vient de s'arrêter (terminée ou en attente d'une suite).
        let stopped = knownWorking.subtracting(working).subtracting(waiting)
        if sessions.contains(where: { stopped.contains($0.id) && $0.state == .finished }) {
            celebrateUntil = Date().addingTimeInterval(Self.celebrationDuration)
            MascotSounds.shared.play(.happy)
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
        AnyView(AgentsSettingsView(claude: claude))
    }

    /// Garde l'encoche ouverte pendant la saisie d'un message.
    func holdExpanded(_ hold: Bool) {
        context.holdExpanded(hold)
    }
}
