import SwiftUI

struct AssistantExpandedView: View {
    let module: AssistantModule
    @Environment(\.widgetSize) private var size
    @State private var question = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        if module.mode == .web {
            webBody
        } else {
            apiBody
        }
    }

    /// Mode « site officiel » : visage et un bouton par service.
    private var webBody: some View {
        HStack(spacing: 12) {
            if size != .small {
                AssistantFace(mood: .idle, size: 56)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ouvrir avec mon compte")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 6) {
                    ForEach(WebAssistantService.allCases) { service in
                        Button { module.openWeb(service) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: service.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(service.title)
                                    .font(.system(size: 9, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(.white.opacity(service == module.webService ? 0.18 : 0.08),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir \(service.title)")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var apiBody: some View {
        HStack(alignment: .top, spacing: 10) {
            if size != .small {
                VStack(spacing: 4) {
                    AssistantFace(mood: module.mood, size: 56)
                    Text(shortModelName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .frame(width: 64)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                transcript
                inputField
            }
        }
        .padding(10)
        .onChange(of: isTyping) { _, typing in module.holdExpanded(typing) }
    }

    private var shortModelName: String {
        module.model.replacingOccurrences(of: "claude-", with: "")
    }

    @ViewBuilder
    private var transcript: some View {
        if !module.hasKey && module.provider == .claude {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ajoutez votre clé API pour discuter avec l'assistant.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                Button("Configurer…") { module.openSettings() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if module.messages.isEmpty && module.lastError == nil {
            Text("Bonjour ! Posez-moi une question.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(module.messages) { message in
                            Text(message.text.isEmpty ? "…" : message.text)
                                .font(.system(size: message.role == .user ? 10 : 11, weight: message.role == .user ? .medium : .regular))
                                .foregroundStyle(message.role == .user ? .white.opacity(0.55) : .white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(message.id)
                        }
                        if let error = module.lastError {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: module.messages.last?.text) {
                    if let id = module.messages.last?.id { reader.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputField: some View {
        HStack(spacing: 6) {
            TextField("Demander quelque chose…", text: $question)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isTyping)
                .onSubmit(send)
            if module.isResponding {
                Button(action: module.cancel) { Image(systemName: "stop.circle.fill") }
                    .help("Arrêter")
            } else {
                Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Envoyer")
            }
            if !module.messages.isEmpty {
                Button(action: module.newConversation) { Image(systemName: "square.and.pencil") }
                    .help("Nouvelle conversation")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private func send() {
        module.ask(question)
        question = ""
    }
}

// MARK: - Réglages

struct AssistantSettingsView: View {
    @Bindable var module: AssistantModule
    @State private var keyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $module.mode) {
                ForEach(AssistantModule.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if module.mode == .web {
                webSettings
            } else {
                apiSettings
            }
        }
    }

    private var webSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ForEach(WebAssistantService.allCases) { service in
                    Button("Ouvrir \(service.title)") { module.openWeb(service) }
                }
            }
            Text("Le site officiel s'ouvre dans une fenêtre sous l'encoche : connectez-vous une fois avec votre compte, la session est conservée. Votre abonnement (ChatGPT Plus, Gemini Advanced, SuperGrok…) s'applique normalement.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var apiSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Fournisseur", selection: $module.provider) {
                ForEach(AIProviderKind.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            if module.provider == .openAICompatible {
                LabeledContent("Adresse de l'API") {
                    TextField("https://api.openai.com/v1", text: $module.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Exemples : https://api.openai.com/v1 · https://api.mistral.ai/v1 · http://localhost:11434/v1 (Ollama, sans clé).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Clé API") {
                HStack {
                    SecureField(module.hasKey ? "Enregistrée dans le trousseau" : "Coller la clé", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Enregistrer") {
                        module.saveKey(keyDraft)
                        keyDraft = ""
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if module.hasKey {
                        Button("Supprimer", role: .destructive, action: module.deleteKey)
                    }
                }
            }

            LabeledContent("Modèle") {
                HStack {
                    if module.availableModels.isEmpty {
                        TextField(module.provider.defaultModel, text: $module.model)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Modèle", selection: $module.model) {
                            ForEach(module.availableModels, id: \.self) { Text($0).tag($0) }
                            if !module.availableModels.contains(module.model) { Text(module.model).tag(module.model) }
                        }
                        .labelsHidden()
                    }
                    Button("Charger la liste", action: module.loadModels)
                }
            }
            if let status = module.modelsStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Text("L'utilisation de l'API est facturée par le fournisseur sur votre compte API (séparément d'un abonnement Claude Pro/Max). La clé reste dans le trousseau de ce Mac. Avec Claude, si une demande est refusée par les filtres de sécurité d'un modèle récent, elle est automatiquement relancée sur un autre modèle Claude (« fallbacks »).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
