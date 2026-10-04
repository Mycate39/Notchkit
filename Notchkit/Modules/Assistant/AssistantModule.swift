import AppKit
import SwiftUI
import Observation

/// Module Assistant IA : posez une question depuis l'encoche, la réponse arrive en direct,
/// accompagnée d'un visage animé. Fournisseur au choix (Claude ou API compatible OpenAI).
///
/// ⚠️ L'utilisation de l'API est facturée par le fournisseur, sur votre compte API
/// (séparément d'un abonnement Claude Pro/Max).
@MainActor
@Observable
final class AssistantModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "assistant",
        name: "Assistant IA",
        summary: "Posez une question depuis l'encoche (Claude ou API compatible OpenAI), avec un visage animé.",
        systemImage: "face.smiling",
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    /// Nombre de messages gardés en mémoire pour le contexte de la conversation.
    static let maxHistory = 20

    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    private(set) var isWaitingFirstToken = false
    private(set) var lastError: String?
    private(set) var availableModels: [String] = []
    private(set) var modelsStatus: String?

    // MARK: Réglages

    var provider: AIProviderKind {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider)
            if provider != oldValue {
                model = UserDefaults.standard.string(forKey: Keys.model(provider)) ?? provider.defaultModel
                availableModels = []
                hasKey = Keychain.read(provider.keychainAccount)?.isEmpty == false
            }
        }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model(provider)) }
    }
    /// Adresse de l'API compatible OpenAI (ex. https://api.openai.com/v1, http://localhost:11434/v1 pour Ollama).
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }
    private(set) var hasKey = false

    private enum Keys {
        static let provider = "module.assistant.provider"
        static let baseURL = "module.assistant.baseURL"
        static func model(_ provider: AIProviderKind) -> String { "module.assistant.model.\(provider.rawValue)" }
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var task: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: Keys.provider).flatMap(AIProviderKind.init(rawValue:)) ?? .claude
        self.provider = provider
        model = defaults.string(forKey: Keys.model(provider)) ?? provider.defaultModel
        baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        hasKey = Keychain.read(provider.keychainAccount)?.isEmpty == false
    }

    func stop() {
        task?.cancel()
    }

    // MARK: Clé API

    func saveKey(_ key: String) {
        Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainAccount)
        hasKey = Keychain.read(provider.keychainAccount)?.isEmpty == false
    }

    func deleteKey() {
        Keychain.delete(provider.keychainAccount)
        hasKey = false
    }

    // MARK: Conversation

    var mood: AssistantFace.Mood {
        if lastError != nil { return .error }
        if isWaitingFirstToken { return .thinking }
        if isResponding { return .speaking }
        return .idle
    }

    func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        lastError = nil
        messages.append(ChatMessage(role: .user, text: text))
        messages = Array(messages.suffix(Self.maxHistory))
        let history = messages
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true
        isWaitingFirstToken = true

        let provider = self.provider, model = self.model, baseURL = self.baseURL
        let key = Keychain.read(provider.keychainAccount)
        task = Task { [weak self] in
            do {
                for try await event in AIClient.stream(provider: provider, baseURL: baseURL, apiKey: key, model: model, messages: history) {
                    guard let self else { return }
                    switch event {
                    case let .text(chunk):
                        self.isWaitingFirstToken = false
                        self.appendToAnswer(chunk)
                    case let .stop(reason):
                        if reason == "refusal" {
                            // Réponse refusée par les filtres de sécurité : la partie reçue est retirée.
                            self.replaceAnswer(String(localized: "Le modèle a refusé de répondre à cette demande."))
                        }
                    case let .failure(message):
                        self.lastError = message
                    }
                }
            } catch is CancellationError {
            } catch {
                self?.lastError = error.localizedDescription
            }
            self?.finishResponse()
        }
    }

    func cancel() {
        task?.cancel()
        finishResponse()
    }

    func newConversation() {
        cancel()
        messages.removeAll()
        lastError = nil
    }

    private func appendToAnswer(_ chunk: String) {
        guard let index = messages.indices.last, messages[index].role == .assistant else { return }
        messages[index].text += chunk
    }

    private func replaceAnswer(_ text: String) {
        guard let index = messages.indices.last, messages[index].role == .assistant else { return }
        messages[index].text = text
    }

    private func finishResponse() {
        isResponding = false
        isWaitingFirstToken = false
        // Réponse vide (erreur avant le premier mot) : on retire la bulle vide.
        if let last = messages.last, last.role == .assistant, last.text.isEmpty { messages.removeLast() }
    }

    // MARK: Modèles

    func loadModels() {
        modelsStatus = String(localized: "Chargement…")
        let provider = self.provider, baseURL = self.baseURL
        let key = Keychain.read(provider.keychainAccount)
        Task { [weak self] in
            do {
                let models = try await AIClient.listModels(provider: provider, baseURL: baseURL, apiKey: key)
                self?.availableModels = models
                self?.modelsStatus = models.isEmpty ? String(localized: "Aucun modèle trouvé") : String(localized: "\(models.count) modèles disponibles")
            } catch {
                self?.modelsStatus = error.localizedDescription
            }
        }
    }

    func holdExpanded(_ hold: Bool) {
        context.holdExpanded(hold)
    }

    func openSettings() {
        context.openSettings()
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { isResponding ? .normal : .none }

    var expandedWidthWeight: CGFloat { 2 }

    func compactLeading() -> AnyView? {
        guard isResponding else { return nil }
        return AnyView(AssistantFace(mood: mood, size: 20))
    }

    func compactTrailing() -> AnyView? {
        guard isResponding else { return nil }
        return AnyView(Text(isWaitingFirstToken ? "…" : String(localized: "Réponse")).foregroundStyle(.white.opacity(0.8)))
    }

    func miniView() -> AnyView {
        AnyView(MiniWidget(value: nil, caption: String(localized: "Assistant")) {
            AssistantFace(mood: mood, size: 34)
        })
    }

    func expandedView() -> AnyView {
        AnyView(AssistantExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(AssistantSettingsView(module: self))
    }
}
