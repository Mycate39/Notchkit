import SwiftUI

// MARK: - Carte dans l'encoche dépliée

struct ClaudeExpandedView: View {
    let module: ClaudeModule

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
                activity(session)
                Spacer(minLength: 0)
                if session != nil { messageField(session!) }
                usageRow
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
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .lineLimit(1)
    }

    private func title(_ session: ClaudeSession?) -> LocalizedStringKey {
        switch session?.state {
        case .working: "Claude travaille"
        case .waitingForPermission: "Claude attend votre accord"
        case .awaitingReply, .finished: "Claude a terminé"
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
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.1), in: Capsule())

            if session.state == .awaitingReply, let deadline = session.replyDeadline {
                HStack(spacing: 3) {
                    Text("Répondez pour qu'il continue")
                    Text("·")
                    ReplyCountdown(deadline: deadline)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
                .lineLimit(1)
            } else if let pending = module.pendingMessages[session.id], !pending.isEmpty {
                Text(session.state == .finished
                     ? "Message en attente : il sera remis avec votre prochaine demande dans Claude Code."
                     : "Message en attente : remis à la prochaine étape de Claude.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    @ViewBuilder
    private var usageRow: some View {
        if let usage = module.usage {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let reset = usage.resetAt {
                        Text("≈ \(usage.currentTokens.formatted(.number.notation(.compactName))) tokens")
                        Text("·")
                        Text("réinitialisation \(reset, format: .relative(presentation: .named))")
                    } else {
                        Text("Aucune session d'utilisation en cours")
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

                if usage.resetAt != nil, usage.personalMax > 0 {
                    GeometryReader { proxy in
                        let ratio = min(1, Double(usage.currentTokens) / Double(usage.personalMax))
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(Color(nsColor: ClaudeSparkView.color))
                                .frame(width: proxy.size.width * ratio)
                        }
                    }
                    .frame(height: 3)
                    .help("Par rapport à votre plus grosse session observée (estimation)")
                }
            }
        }
    }

    private func send() {
        module.send(draft)
        draft = ""
        isTyping = false
    }
}

// MARK: - Réglages

struct ClaudeSettingsView: View {
    @Bindable var module: ClaudeModule
    @State private var confirmInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Afficher l'activité quand l'encoche est repliée", isOn: $module.showInCompact)
            Toggle("Alerte quand Claude a terminé", isOn: $module.alertOnFinish)
            Picker("Délai pour répondre depuis l'encoche", selection: $module.replyWindow) {
                ForEach(ClaudeModule.replyWindowChoices, id: \.self) { seconds in
                    if seconds == 0 {
                        Text("Désactivé").tag(seconds)
                    } else {
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))).tag(seconds)
                    }
                }
            }
            Text("Après chaque réponse de Claude, vous pouvez encore lui écrire depuis l'encoche pendant ce délai : il repart aussitôt. Pendant ce temps, Claude Code l'affiche comme « en cours » (Échap pour arrêter).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

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
                }
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

            Text("L'utilisation est estimée à partir des fichiers de session de Claude Code sur ce Mac (sessions de 5 h). Les conversations sur claude.ai ne sont pas comptées, et la jauge compare à votre plus grosse session observée : Anthropic ne publie pas les plafonds exacts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Installer l'intégration Claude Code ?", isPresented: $confirmInstall) {
            Button("Installer", action: module.installHooks)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Notchkit va ajouter des hooks dans ~/.claude/settings.json pour que Claude Code le prévienne de son activité (connexion locale uniquement, protégée par un jeton). Vos réglages existants sont conservés et une copie de sauvegarde est faite. Les nouvelles sessions de Claude Code en tiendront compte.")
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

/// Compte à rebours de la fenêtre de réponse, ex. « 1:45 ».
struct ReplyCountdown: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
        }
    }
}
