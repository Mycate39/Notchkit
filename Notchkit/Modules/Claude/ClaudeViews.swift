import SwiftUI

// MARK: - Carte dans l'encoche dépliée

struct ClaudeExpandedView: View {
    let module: ClaudeModule
    @Environment(\.widgetSize) private var size

    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        Group {
            if !module.hooksInstalled {
                setupPrompt
            } else {
                content
            }
        }
        .padding(12)
        .onChange(of: isTyping) { _, typing in
            // Pendant la saisie, l'encoche reste dépliée même si la souris s'éloigne.
            module.holdExpanded(typing)
        }
        .onDisappear { module.holdExpanded(false) }
    }

    private var setupPrompt: some View {
        HStack(spacing: 12) {
            ClaudeSparkView(isAnimating: false)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(module.installStatus == .outdated ? "Mettez à jour l'intégration" : "Connectez Claude Code")
                    .font(.system(size: 12, weight: .semibold))
                Text("Installez l'intégration pour suivre ce que fait Claude et lui écrire depuis l'encoche.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Configurer…", action: module.openSettings)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var content: some View {
        let session = module.displayedSession

        return HStack(alignment: .top, spacing: 10) {
            ClaudeSparkView(isAnimating: session?.state == .working)
                .frame(width: 28, height: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                header(session)
                if let session, !session.conversation.isEmpty, size != .small {
                    // Messages en direct, avec l'historique qui défile verticalement.
                    ClaudeConversationView(session: session)
                        .frame(maxHeight: .infinity)
                } else {
                    activity(session)
                    Spacer(minLength: 0)
                }
                if let session, size != .small {
                    messageField(session)
                } else if session == nil {
                    usageRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ session: ClaudeSession?) -> some View {
        HStack(spacing: 6) {
            Text(title(session))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(session?.state == .waitingForPermission ? Color(nsColor: ClaudeSparkView.color) : .white)
            Spacer(minLength: 4)
            if let project = session?.projectName {
                Text(project)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            // Quand une session est affichée, la place manque en bas : l'utilisation passe en badge.
            if session != nil, let line = usageLines.first {
                usageBadge(line)
            }
        }
        .lineLimit(1)
    }

    private func usageBadge(_ line: UsageLine) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 10, weight: .semibold))
            Text(verbatim: (line.isEstimate ? "≈ " : "") + line.fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Self.color(for: line.fraction))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Self.color(for: line.fraction).opacity(0.15), in: Capsule())
        .help(usageLines.map(\.helpText).joined(separator: "\n"))
    }

    private func title(_ session: ClaudeSession?) -> LocalizedStringKey {
        switch session?.state {
        case .working: "Claude travaille"
        case .waitingForPermission: "Claude attend votre accord"
        case .finished: "Claude a terminé"
        case nil: "Claude Code est inactif"
        }
    }

    @ViewBuilder
    private func activity(_ session: ClaudeSession?) -> some View {
        if let session {
            if session.state == .waitingForPermission, let message = session.attentionMessage {
                Text(message)
                    .font(.system(size: 11))
                    .lineLimit(2)
            } else if let action = session.currentAction {
                Label(action.text, systemImage: action.symbol)
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else if let prompt = session.prompt {
                Text("« \(prompt) »")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            // Actions précédentes.
            ForEach(session.recentActions.dropFirst(session.currentAction == nil ? 0 : 1).prefix(2)) { action in
                Label(action.text, systemImage: action.symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        } else {
            Text("L'activité apparaîtra ici dès que Claude Code travaillera.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
        }
    }

    private func messageField(_ session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TextField(session.state == .finished ? "Claude est à l'arrêt : message remis avec votre prochaine demande" : "Écrire à Claude…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isTyping)
                    .onSubmit(send)
                    .onExitCommand { isTyping = false }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
                }
                .buttonStyle(.notch)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(StandBy.surface, in: Capsule())

            if let pending = module.pendingMessages[session.id], !pending.isEmpty {
                Text(session.state == .finished
                     ? "Message en attente : il sera remis avec votre prochaine demande dans Claude Code."
                     : "Message en attente : remis à la prochaine étape de Claude.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    /// Lignes d'utilisation : réelles (barre d'état de Claude Code) si disponibles, sinon estimées.
    private var usageLines: [UsageLine] {
        let now = Date()
        if let limits = module.rateLimits {
            var lines: [UsageLine] = []
            if let window = limits.fiveHour {
                lines.append(UsageLine(label: "Session", fraction: window.fraction(at: now), resetAt: window.resetsAt > now ? window.resetsAt : nil, isEstimate: false))
            }
            if let window = limits.sevenDay {
                lines.append(UsageLine(label: "Semaine", fraction: window.fraction(at: now), resetAt: window.resetsAt > now ? window.resetsAt : nil, isEstimate: false))
            }
            if !lines.isEmpty { return lines }
        }
        if let usage = module.usage, let fraction = usage.usedFraction {
            return [UsageLine(label: "Session", fraction: fraction, resetAt: usage.resetAt, isEstimate: true)]
        }
        return []
    }

    @ViewBuilder
    private var usageRow: some View {
        let lines = usageLines
        if lines.isEmpty {
            Text("Aucune session d'utilisation en cours")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(lines) { line in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(line.label)
                                .font(.system(size: 10, weight: .semibold))
                            if let reset = line.resetAt {
                                Text(Self.resetText(reset))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        // Petit widget : pas de largeur fixe ni de jauge, sinon la ligne élargit la carte.
                        .frame(width: size == .small ? nil : 112, alignment: .leading)
                        .frame(maxWidth: size == .small ? .infinity : nil, alignment: .leading)

                        if size != .small {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.15))
                                    Capsule().fill(Self.color(for: line.fraction))
                                        .frame(width: max(4, proxy.size.width * line.fraction))
                                }
                            }
                            .frame(height: 5)
                        }

                        Text(verbatim: (line.isEstimate ? "≈ " : "") + line.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Self.color(for: line.fraction))
                            .frame(width: 46, alignment: .trailing)
                    }
                    .lineLimit(1)
                    .help(line.helpText)
                }
                if lines.contains(where: \.isEstimate) {
                    Text("Estimation locale : installez l'intégration (barre d'état) pour les chiffres réels.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    /// Ex. « Réinitialisation à 15:00 » ou « Réinit. vendredi 03:00 ».
    nonisolated static func resetText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return String(localized: "Réinitialisation à \(date.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Réinit. \(date.formatted(.dateTime.weekday(.wide).hour().minute()))")
    }

    /// Orange en temps normal, puis jaune et rouge à l'approche du plafond estimé.
    private static func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: Color(nsColor: ClaudeSparkView.color)
        case ..<0.9: .yellow
        default: .red
        }
    }

    private func send() {
        module.send(draft)
        draft = ""
        isTyping = false
    }
}

// MARK: - Réglages

/// Intégration Claude Code (hooks et barre d'état), réglée depuis la page du widget Agents.
struct ClaudeIntegrationView: View {
    @Bindable var module: ClaudeModule
    @State private var confirmInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(statusText, systemImage: module.hooksInstalled ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(module.hooksInstalled ? .green : .secondary)
                Spacer()
                switch module.installStatus {
                case .installed:
                    Button("Désinstaller", action: module.uninstallHooks)
                case .outdated:
                    Button("Mettre à jour l'intégration", action: module.installHooks)
                case .notInstalled:
                    Button("Installer l'intégration…") { confirmInstall = true }
                        .buttonStyle(.borderedProminent)
                }
            }

            if module.hasCustomStatusLine {
                Text("Vous avez déjà votre propre barre d'état Claude Code : Notchkit ne la remplace pas, l'utilisation affichée reste donc une estimation.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case let .failed(reason) = module.serverState {
                Text("Le serveur local n'a pas pu démarrer sur le port \(String(module.port)) : \(reason)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let message = module.installerMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("L'utilisation réelle (session de 5 h et semaine) est transmise par Claude Code à sa barre d'état, à chaque message. En attendant ces données, Notchkit affiche une estimation calculée à partir des fichiers de session locaux.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Installer l'intégration Claude Code ?", isPresented: $confirmInstall) {
            Button("Installer", action: module.installHooks)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Notchkit va ajouter des hooks et une barre d'état dans ~/.claude/settings.json pour que Claude Code le prévienne de son activité et lui transmette votre utilisation réelle (connexion locale uniquement, protégée par un jeton). Vos réglages existants sont conservés et une copie de sauvegarde est faite. Les nouvelles sessions de Claude Code en tiendront compte.")
        }
        .onAppear { module.refreshInstallState() }
    }

    private var statusText: LocalizedStringKey {
        switch module.installStatus {
        case .installed: "Intégration Claude Code installée"
        case .outdated: "Mise à jour de l'intégration nécessaire"
        case .notInstalled: "Intégration Claude Code non installée"
        }
    }
}

/// Une ligne d'utilisation (session de 5 h ou semaine).
struct UsageLine: Identifiable {
    let label: LocalizedStringKey
    let fraction: Double
    let resetAt: Date?
    /// Vrai pour l'estimation locale (faute de données réelles).
    let isEstimate: Bool

    var id: String { "\(label)" }

    var helpText: String {
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        let reset = resetAt.map { " · " + ClaudeExpandedView.resetText($0) } ?? ""
        return isEstimate
            ? String(localized: "Estimation : \(percent)\(reset). Comparée à votre plus grosse session observée.")
            : String(localized: "\(percent) utilisés\(reset) (chiffres transmis par Claude Code).")
    }
}

// MARK: - Conversation

/// Historique des messages (demandes et réponses de Claude), défilant verticalement.
/// Suit automatiquement le dernier message ; la barre de défilement reste visible.
struct ClaudeConversationView: View {
    let session: ClaudeSession

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(session.conversation) { entry in
                        ClaudeChatBubble(entry: entry)
                            .id(entry.id)
                    }
                    // Ce que Claude fait en ce moment, sous le dernier message.
                    if session.state == .working, let action = session.currentAction {
                        Label(action.text, systemImage: action.symbol)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .id("action")
                    } else if session.state == .waitingForPermission, let message = session.attentionMessage {
                        Label(message, systemImage: "hand.raised")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
                            .lineLimit(2)
                            .id("action")
                    }
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(.trailing, 10)  // place pour la barre de défilement
            }
            .scrollIndicators(.visible)
            .onAppear { reader.scrollTo("fin", anchor: .bottom) }
            .onChange(of: session.conversation.last?.id) {
                withAnimation(.spring(duration: 0.35, bounce: 0)) { reader.scrollTo("fin", anchor: .bottom) }
            }
            .onChange(of: session.currentAction?.id) {
                reader.scrollTo("fin", anchor: .bottom)
            }
        }
    }
}

/// Un message : réponse de Claude à gauche (texte clair), demande de l'utilisateur à droite (bulle discrète).
private struct ClaudeChatBubble: View {
    let entry: ClaudeChatEntry

    var body: some View {
        switch entry.role {
        case .claude:
            Text(Self.markdown(entry.text))
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .user:
            Text(entry.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(3)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Gras, italique, code et liens (le reste du Markdown est affiché tel quel).
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Réponse à une demande d'autorisation depuis la bulle de Claude Code : Autoriser en vert,
/// Refuser en gris, comme les commandes de la bulle du minuteur.
struct ClaudeBubbleControls: View {
    let module: ClaudeModule
    let sessionID: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            control("checkmark", tint: .green, help: "Autoriser") {
                module.decidePermission(sessionID, allow: true)
            }
            Spacer(minLength: 0)
            control("xmark", tint: .white, help: "Refuser") {
                module.decidePermission(sessionID, allow: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func control(_ symbol: String, tint: Color, help: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.22), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.notch)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
