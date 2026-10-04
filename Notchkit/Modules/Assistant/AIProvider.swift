import Foundation

/// Fournisseur d'IA de l'assistant.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    /// API Claude d'Anthropic.
    case claude
    /// Toute API « compatible OpenAI » (OpenAI, Mistral, Ollama en local…).
    case openAICompatible

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .claude: "Claude (Anthropic)"
        case .openAICompatible: "Compatible OpenAI"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: "claude-opus-5-5"
        case .openAICompatible: "gpt-4o-mini"
        }
    }

    var keychainAccount: String { rawValue }
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

/// Morceau de réponse reçu en direct.
enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    /// Fin de la réponse, avec la raison d'arrêt si connue (« end_turn », « refusal »…).
    case stop(String?)
    case failure(String)
}

enum AIError: LocalizedError {
    case missingKey
    case invalidURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "Clé API manquante : ajoutez-la dans les réglages de l'assistant.")
        case .invalidURL: String(localized: "Adresse du fournisseur invalide.")
        case let .http(code, message): String(localized: "Erreur \(code) : \(message)")
        }
    }
}

// MARK: - Lecture des flux (fonctions pures, testées)

/// Flux SSE de l'API Messages de Claude.
enum ClaudeSSE {
    /// Interprète une ligne « data: {…} ».
    static func parse(_ line: String) -> AIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .text(text)
        case "message_delta":
            let reason = (json["delta"] as? [String: Any])?["stop_reason"] as? String
            return reason.map { .stop($0) }
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? String(localized: "Erreur inconnue")
            return .failure(message)
        default:
            return nil
        }
    }
}

/// Flux SSE des API compatibles OpenAI (« chat/completions »).
enum OpenAISSE {
    static func parse(_ line: String) -> AIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .stop(nil) }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let error = json["error"] as? [String: Any] {
            return .failure(error["message"] as? String ?? String(localized: "Erreur inconnue"))
        }
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return nil }
        if let content = (choice["delta"] as? [String: Any])?["content"] as? String, !content.isEmpty {
            return .text(content)
        }
        if let reason = choice["finish_reason"] as? String { return .stop(reason) }
        return nil
    }
}

// MARK: - Requêtes

enum AIClient {
    static let claudeBaseURL = URL(string: "https://api.anthropic.com/v1")!

    /// Modèles Claude pour lesquels le repli automatique côté serveur est proposé par défaut
    /// (si le filtre de sécurité refuse une demande, l'API la relance sur un autre modèle).
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-fable-5-1", "claude-opus-5", "claude-sonnet-5-5"]

    static let systemPrompt = """
    Tu es l'assistant intégré à Notchkit, une app qui vit dans l'encoche du Mac. \
    Tes réponses s'affichent dans un petit espace : sois clair et concis, va à l'essentiel, \
    évite les longues listes et le Markdown lourd. Réponds dans la langue de l'utilisateur.
    """

    /// Corps de requête Claude (fonction pure, testée).
    static func claudeBody(model: String, messages: [ChatMessage]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 64000,
            "stream": true,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if fallbackModels.contains(model) { body["fallbacks"] = "default" }
        return body
    }

    static func openAIBody(model: String, messages: [ChatMessage]) -> [String: Any] {
        [
            "model": model,
            "stream": true,
            "messages": [["role": "system", "content": systemPrompt]]
                + messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
    }

    /// Réponse en direct.
    static func stream(provider: AIProviderKind, baseURL: String, apiKey: String?, model: String,
                       messages: [ChatMessage]) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(provider: provider, baseURL: baseURL, apiKey: apiKey,
                                                      model: model, messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIError.http(status, errorMessage(from: body))
                    }
                    for try await line in bytes.lines {
                        let event = provider == .claude ? ClaudeSSE.parse(line) : OpenAISSE.parse(line)
                        if let event { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func makeChatRequest(provider: AIProviderKind, baseURL: String, apiKey: String?, model: String,
                                messages: [ChatMessage]) throws -> URLRequest {
        switch provider {
        case .claude:
            guard let apiKey, !apiKey.isEmpty else { throw AIError.missingKey }
            var request = URLRequest(url: claudeBaseURL.appendingPathComponent("messages"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if fallbackModels.contains(model) {
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: claudeBody(model: model, messages: messages))
            request.timeoutInterval = 600
            return request
        case .openAICompatible:
            guard let base = URL(string: baseURL), base.scheme != nil else { throw AIError.invalidURL }
            var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: openAIBody(model: model, messages: messages))
            request.timeoutInterval = 600
            return request
        }
    }

    /// Liste des modèles proposés par le fournisseur.
    static func listModels(provider: AIProviderKind, baseURL: String, apiKey: String?) async throws -> [String] {
        var request: URLRequest
        switch provider {
        case .claude:
            guard let apiKey, !apiKey.isEmpty else { throw AIError.missingKey }
            var components = URLComponents(url: claudeBaseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
            request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAICompatible:
            guard let base = URL(string: baseURL), base.scheme != nil else { throw AIError.invalidURL }
            request = URLRequest(url: base.appendingPathComponent("models"))
            if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization") }
        }
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AIError.http(status, errorMessage(from: String(decoding: data, as: UTF8.self))) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ids = (json?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        return provider == .claude ? ids.filter { $0.hasPrefix("claude-") } : ids.sorted()
    }

    static func errorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return String(body.prefix(200)) }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = json["message"] as? String { return message }
        return String(body.prefix(200))
    }
}
