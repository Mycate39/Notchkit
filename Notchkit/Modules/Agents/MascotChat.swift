import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Discussion avec la mascotte : Apple Intelligence (sur le Mac, gratuit, hors ligne) ou Claude
/// (clé API de l'utilisateur, pour les questions difficiles).
@MainActor
@Observable
final class MascotChat {
    enum Engine: String, CaseIterable, Identifiable {
        case appleIntelligence
        case claude

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appleIntelligence: "Apple Intelligence"
            case .claude: "Claude"
            }
        }
    }

    /// Disponibilité d'Apple Intelligence sur ce Mac.
    enum AppleAvailability: Equatable {
        case available
        case notEnabled
        case notEligible
        case notReady
        case unsupportedSystem
    }

    /// Modèle Claude utilisé dans l'encoche : rapide, pour des réponses courtes.
    static let claudeModel = "claude-sonnet-5-5"
    static let claudeKeychainAccount = AIProviderKind.claude.keychainAccount
    private static let engineKey = "module.agents.chatEngine"
    /// Au-delà, les plus anciens messages sont oubliés (place limitée dans l'encoche).
    static let maxMessages = 30

    var engine: Engine {
        didSet {
            UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey)
            reset()
        }
    }
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    private(set) var errorMessage: String?
    private(set) var hasClaudeKey: Bool

    @ObservationIgnored private let persona: @MainActor () -> String
    @ObservationIgnored private let agentsSummary: @MainActor () -> String
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Session Apple Intelligence (gardée d'une question à l'autre pour le contexte).
    @ObservationIgnored private var appleSession: AnyObject?

    init(persona: @escaping @MainActor () -> String, agentsSummary: @escaping @MainActor () -> String) {
        self.persona = persona
        self.agentsSummary = agentsSummary
        hasClaudeKey = Keychain.read(Self.claudeKeychainAccount)?.isEmpty == false
        let saved = UserDefaults.standard.string(forKey: Self.engineKey).flatMap(Engine.init(rawValue:))
        engine = saved ?? (Self.appleAvailability == .available ? .appleIntelligence : .claude)
    }

    static var appleAvailability: AppleAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
            case .unavailable(.deviceNotEligible): return .notEligible
            case .unavailable: return .notReady
            }
        }
        #endif
        return .unsupportedSystem
    }

    // MARK: Clé Claude

    func saveClaudeKey(_ key: String) {
        _ = Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.claudeKeychainAccount)
        hasClaudeKey = Keychain.read(Self.claudeKeychainAccount)?.isEmpty == false
    }

    func deleteClaudeKey() {
        Keychain.delete(Self.claudeKeychainAccount)
        hasClaudeKey = false
    }

    // MARK: Discussion

    func reset() {
        task?.cancel()
        task = nil
        messages = []
        isResponding = false
        errorMessage = nil
        appleSession = nil
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        messages.append(ChatMessage(role: .assistant, text: ""))
        messages = Array(messages.suffix(Self.maxMessages))
        isResponding = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch self.engine {
                case .appleIntelligence: try await self.answerWithApple(trimmed)
                case .claude: try await self.answerWithClaude()
                }
            } catch is CancellationError {
            } catch {
                self.errorMessage = error.localizedDescription
                // Session Apple trop longue ou en erreur : on repart d'une session neuve.
                self.appleSession = nil
                if self.messages.last?.role == .assistant, self.messages.last?.text.isEmpty == true {
                    self.messages.removeLast()
                }
            }
            self.isResponding = false
        }
    }

    private func updateAnswer(_ text: String) {
        guard let index = messages.indices.last, messages[index].role == .assistant else { return }
        messages[index].text = text
    }

    private func answerWithClaude() async throws {
        let history = messages.filter { !($0.role == .assistant && $0.text.isEmpty) }
        let key = Keychain.read(Self.claudeKeychainAccount)
        var answer = ""
        for try await event in AIClient.stream(provider: .claude, baseURL: "", apiKey: key, model: Self.claudeModel, messages: history) {
            switch event {
            case let .text(chunk):
                answer += chunk
                updateAnswer(answer)
            case let .failure(message):
                throw NSError(domain: "Notchkit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            case .stop:
                break
            }
        }
    }

    private func answerWithApple(_ prompt: String) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session: LanguageModelSession
            if let existing = appleSession as? LanguageModelSession {
                session = existing
            } else {
                let summary = agentsSummary
                let tool = AgentsStatusTool(read: { await MainActor.run { summary() } })
                session = LanguageModelSession(tools: [tool], instructions: persona())
                appleSession = session
            }
            for try await snapshot in session.streamResponse(to: prompt) {
                updateAnswer(snapshot.content)
            }
            return
        }
        #endif
        throw NSError(domain: "Notchkit", code: 2, userInfo: [NSLocalizedDescriptionKey:
            String(localized: "Apple Intelligence n'est pas disponible sur ce Mac.")])
    }
}

#if canImport(FoundationModels)
/// Outil d'Apple Intelligence : l'état réel des agents de code, pour que la mascotte puisse en parler.
@available(macOS 26, *)
struct AgentsStatusTool: Tool {
    let name = "etatDesAgents"
    let description = "Donne l'état actuel des agents de code (Claude Code) : projets, ce qu'ils font et s'ils attendent une réponse."

    @Generable
    struct Arguments {
        @Guide(description: "Nom du projet à détailler, ou chaîne vide pour tous les projets")
        var projet: String
    }

    let read: @Sendable () async -> String

    func call(arguments: Arguments) async throws -> String {
        await read()
    }
}
#endif
