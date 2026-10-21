import SwiftUI

/// Page des agents : à gauche la mascotte et la session suivie, à droite ses étapes.
/// Plusieurs sessions : des pastilles en haut à droite permettent de passer de l'une à l'autre.
struct AgentsHomeView: View {
    let module: AgentsModule
    @State private var selectedID: String?

    private var sessions: [ClaudeSession] { module.sessions }

    /// Session affichée : celle choisie, sinon celle qui attend une réponse, sinon la plus récente.
    private var session: ClaudeSession? {
        let sessions = sessions
        if let selectedID, let chosen = sessions.first(where: { $0.id == selectedID }) { return chosen }
        return sessions.first { $0.state == .waitingForPermission } ?? sessions.first
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let celebrating = (module.celebrateUntil ?? .distantPast) > context.date
            // Question ou autorisation de Claude : le panneau prend toute la place (mascotte seule à gauche)
            // pour que la question et ses choix s'affichent en entier.
            let needsRoom = session?.questionPrompt != nil || session?.permissionPrompt != nil
            HStack(spacing: 10) {
                if needsRoom {
                    LiveMascotView(design: module.mascot, mood: .waiting, size: 34, reactsToTap: true)
                        .frame(width: 52)
                        .transition(.opacity)
                } else {
                    identity(celebrating: celebrating)
                        .frame(width: 214, alignment: .leading)
                        .transition(.opacity)
                }
                VStack(alignment: .trailing, spacing: 5) {
                    if !needsRoom && sessions.count > 1 {
                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            sessionPills
                        }
                    }
                    workPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            // Marges serrées : en taille Compacte, la page n'a qu'environ 120 points de haut.
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: Mascotte, session et étapes

    private func identity(celebrating: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            LiveMascotView(design: module.mascot,
                           mood: AgentsModule.mood(for: session, celebrating: celebrating),
                           size: 42,
                           reactsToTap: true)
                .frame(width: 66, height: 62)
            VStack(alignment: .leading, spacing: 1) {
                if let session {
                    Text(session.projectName ?? String(localized: "Session"))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(verbatim: "Claude Code")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    AgentPhaseList(session: session)
                        .padding(.top, 3)
                } else {
                    Text("Aucun agent au travail")
                        .font(.system(size: 14, weight: .semibold))
                    Text(module.claude?.hooksInstalled == true
                         ? "Lancez une demande dans Claude Code : la mascotte suivra son travail ici."
                         : "Activez Claude Code dans les réglages pour suivre ses sessions ici.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Travail en cours

    /// Panneau de droite : la dernière modification (éditeur), la dernière commande (terminal),
    /// la demande d'accord, ou à défaut la liste des actions.
    @ViewBuilder
    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let session, let prompt = session.questionPrompt {
                    AgentQuestionPanel(prompt: prompt,
                                       onAnswer: { module.claude?.answerQuestions(session.id, selections: $0) },
                                       onTerminal: { module.claude?.answerInTerminal(session.id) })
                        .id(session.id)
                } else if let session, let prompt = session.permissionPrompt {
                    AgentDecisionPanel(prompt: prompt,
                                       onDecide: { allow, always in module.claude?.decidePermission(session.id, allow: allow, always: always) },
                                       onTerminal: { module.claude?.answerInTerminal(session.id) })
                } else if let session, session.state == .waitingForPermission {
                    AgentPermissionPanel(session: session)
                } else if let session, let edit = session.lastEdit,
                          (session.lastEditAt ?? .distantPast) >= (session.lastCommandAt ?? .distantPast) {
                    AgentEditorPanel(edit: edit, editedAt: session.lastEditAt ?? .now, isLive: session.state == .working)
                        .id(session.lastEditAt)
                } else if let session, let command = session.lastCommand {
                    AgentTerminalPanel(command: command, isLive: session.state == .working)
                } else if let session, !session.recentActions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(session.recentActions.prefix(4).reversed()), id: \.id) { action in
                            AgentStepRow(action: action, isCurrent: session.state == .working && action.id == session.currentAction?.id)
                        }
                    }
                } else {
                    Text(session == nil ? "Les étapes de l'agent s'afficheront ici." : "Pas encore d'étape.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(NotchLayout.pageIndicatorSpring, value: session?.lastEditAt)
        .animation(NotchLayout.pageIndicatorSpring, value: session?.lastCommandAt)
    }

    private var sessionPills: some View {
        HStack(spacing: 6) {
            ForEach(sessions.prefix(4)) { item in
                Button {
                    withAnimation(NotchLayout.pageIndicatorSpring) { selectedID = item.id }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(AgentStateLabel.color(for: item.state)).frame(width: 6, height: 6)
                        Text(item.projectName ?? String(localized: "Session"))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(item.id == session?.id ? StandBy.surface : .clear, in: Capsule())
                }
                .buttonStyle(.notch)
            }
        }
    }
}

/// État d'une session : pastille de couleur et texte court.
struct AgentStateLabel: View {
    let state: ClaudeSession.State

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Self.color(for: state)).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.color(for: state))
        }
    }

    private var text: LocalizedStringKey {
        switch state {
        case .working: "Au travail"
        case .waitingForPermission: "Attend votre accord"
        case .finished: "Terminé"
        }
    }

    static func color(for state: ClaudeSession.State) -> Color {
        switch state {
        case .working: Color(red: 0.35, green: 0.65, blue: 1)
        case .waitingForPermission: StandBy.amber
        case .finished: Color(red: 0.2, green: 0.78, blue: 0.35)
        }
    }
}

/// Une étape : roue qui tourne pour l'étape en cours, coche verte pour les précédentes.
struct AgentStepRow: View {
    let action: ClaudeAction
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isCurrent {
                    AgentSpinner()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.35))
                }
            }
            .frame(width: 16, height: 16)
            Image(systemName: action.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isCurrent ? 0.9 : 0.5))
                .frame(width: 16)
            Text(action.text)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.6))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Roue de l'étape en cours : un arc qui tourne (dessiné en SwiftUI, sans contrôle AppKit).
struct AgentSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color(red: 0.35, green: 0.65, blue: 1), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 13, height: 13)
        }
    }
}

/// Réglages du widget Agents : l'intégration Claude Code.
struct AgentsSettingsView: View {
    let claude: ClaudeModule?

    var body: some View {
        if let claude {
            ClaudeIntegrationView(module: claude)
        }
    }
}
