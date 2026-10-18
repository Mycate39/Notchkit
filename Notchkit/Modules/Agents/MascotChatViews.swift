import SwiftUI

/// Discussion avec la mascotte, dans la page Agents.
struct MascotChatPanel: View {
    let module: AgentsModule
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    private var chat: MascotChat { module.chat }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            messages
            inputRow
        }
        .onChange(of: isTyping) { _, typing in module.holdExpanded(typing) }
        .onDisappear { if isTyping { module.holdExpanded(false) } }
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if chat.messages.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(chat.messages) { message in
                        bubble(message)
                    }
                    if let error = chat.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    }
                    Color.clear.frame(height: 1).id("fin")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onChange(of: chat.messages.last?.text) { reader.scrollTo("fin", anchor: .bottom) }
            .onChange(of: chat.messages.count) { reader.scrollTo("fin", anchor: .bottom) }
        }
    }

    private var emptyText: LocalizedStringKey {
        switch chat.engine {
        case .appleIntelligence:
            MascotChat.appleAvailability == .available
                ? "Posez une question : je réponds avec Apple Intelligence, directement sur votre Mac."
                : "Apple Intelligence n'est pas disponible sur ce Mac : choisissez Claude dans les réglages du widget Agents."
        case .claude:
            chat.hasClaudeKey
                ? "Posez une question à Claude."
                : "Ajoutez votre clé API Claude dans les réglages du widget Agents pour discuter avec Claude."
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(StandBy.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else if message.text.isEmpty {
            TypingDots()
        } else {
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Saisie

    private var inputRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(MascotChat.Engine.allCases) { engine in
                    Button(engine.title) { chat.engine = engine }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(chat.engine == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(red: 0.55, green: 0.5, blue: 1))
                        .frame(width: 6, height: 6)
                    Text(chat.engine.title).font(.system(size: 10, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Moteur de la discussion")

            TextField("Écrire à la mascotte…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isTyping)
                .onSubmit(send)
                .onExitCommand { isTyping = false }
            if !chat.messages.isEmpty {
                Button { chat.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.notch)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Nouvelle discussion")
            }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
            }
            .buttonStyle(.notch)
            .foregroundStyle(.tint)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.isResponding)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private func send() {
        chat.send(draft)
        draft = ""
    }
}

/// Trois points qui rebondissent pendant que la mascotte réfléchit.
private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5)
                        .offset(y: -3 * max(0, sin((t * 2 - Double(index) * 0.2) * .pi)))
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Réglages du widget Agents : moteur de la discussion et clé Claude.
struct AgentsSettingsView: View {
    let chat: MascotChat
    let services: AgentServices
    @State private var key = ""

    var body: some View {
        Picker("Discussion avec la mascotte", selection: Binding(get: { chat.engine }, set: { chat.engine = $0 })) {
            ForEach(MascotChat.Engine.allCases) { engine in
                Text(engine.title).tag(engine)
            }
        }
        Text(appleStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        LabeledContent("Clé API Claude") {
            if chat.hasClaudeKey {
                HStack {
                    Text("Enregistrée dans le trousseau").foregroundStyle(.secondary)
                    Button("Supprimer", role: .destructive) { chat.deleteClaudeKey() }
                }
            } else {
                HStack {
                    SecureField("sk-ant-…", text: $key)
                        .frame(maxWidth: 220)
                    Button("Enregistrer") {
                        chat.saveClaudeKey(key)
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        Text("La clé reste dans le trousseau de votre Mac. Les messages envoyés à Claude passent par l'API d'Anthropic ; avec Apple Intelligence, rien ne quitte votre Mac.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        ServiceKeyRow(title: "Jeton Vercel", placeholder: "Jeton d'accès", isConfigured: services.configured.contains(.vercel),
                      onSave: { services.saveKey($0, for: .vercel) }, onDelete: { services.deleteKey(for: .vercel) })
        ServiceKeyRow(title: "Clé Stripe", placeholder: "rk_live_…", isConfigured: services.configured.contains(.stripe),
                      onSave: { services.saveKey($0, for: .stripe) }, onDelete: { services.deleteKey(for: .stripe) })
        Text("Services en lecture seule : préférez une clé Stripe à accès restreint (lecture des paiements). GitHub utilise le jeton de son propre widget.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var appleStatus: LocalizedStringKey {
        switch MascotChat.appleAvailability {
        case .available: "Apple Intelligence est disponible : gratuit, privé et hors ligne."
        case .notEnabled: "Activez Apple Intelligence dans Réglages Système pour l'utiliser ici."
        case .notEligible: "Ce Mac ne prend pas en charge Apple Intelligence."
        case .notReady: "Apple Intelligence se prépare (téléchargement du modèle) : réessayez plus tard."
        case .unsupportedSystem: "Apple Intelligence demande macOS 26 ou plus récent."
        }
    }
}
