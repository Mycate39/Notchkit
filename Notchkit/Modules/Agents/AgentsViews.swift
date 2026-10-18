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
            HStack(spacing: 14) {
                identity(celebrating: celebrating)
                    .frame(width: 250, alignment: .leading)
                Divider().overlay(.white.opacity(0.08))
                steps
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(14)
        }
    }

    // MARK: Mascotte et session

    private func identity(celebrating: Bool) -> some View {
        HStack(spacing: 12) {
            LiveMascotView(design: module.mascot, mood: AgentsModule.mood(for: session, celebrating: celebrating), size: 52)
                .frame(width: 84, height: 80)
            VStack(alignment: .leading, spacing: 3) {
                if let session {
                    Text(session.projectName ?? String(localized: "Session"))
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Text(verbatim: "Claude Code")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    AgentStateLabel(state: session.state)
                        .padding(.top, 4)
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

    // MARK: Étapes

    @ViewBuilder
    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session?.prompt ?? String(localized: "Étapes"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if sessions.count > 1 { sessionPills }
            }
            if let session, !session.recentActions.isEmpty {
                // De la plus ancienne à la plus récente ; la dernière tourne tant que Claude travaille.
                ForEach(Array(session.recentActions.prefix(4).reversed().enumerated()), id: \.element.id) { index, action in
                    let isCurrent = session.state == .working && action.id == session.currentAction?.id
                    AgentStepRow(action: action, isCurrent: isCurrent)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            } else if session?.state == .waitingForPermission, let message = session?.attentionMessage {
                Label(message, systemImage: "hand.raised.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StandBy.amber)
            } else {
                Text(session == nil ? "Les étapes de l'agent s'afficheront ici." : "Pas encore d'étape.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .animation(NotchLayout.pageIndicatorSpring, value: session?.recentActions.first?.id)
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
        case .awaitingReply: "Terminé, à votre écoute"
        case .finished: "Terminé"
        }
    }

    static func color(for state: ClaudeSession.State) -> Color {
        switch state {
        case .working: Color(red: 0.35, green: 0.65, blue: 1)
        case .waitingForPermission: StandBy.amber
        case .awaitingReply, .finished: Color(red: 0.2, green: 0.78, blue: 0.35)
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
