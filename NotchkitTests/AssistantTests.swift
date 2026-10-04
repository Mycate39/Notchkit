import Foundation
import Testing
@testable import Notchkit

struct AssistantTests {
    @Test func fluxClaude() {
        #expect(ClaudeSSE.parse(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bon"}}"#) == .text("Bon"))
        #expect(ClaudeSSE.parse(#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#) == .stop("end_turn"))
        #expect(ClaudeSSE.parse(#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) == .failure("Overloaded"))
        #expect(ClaudeSSE.parse("event: content_block_delta") == nil)
        #expect(ClaudeSSE.parse(#"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":""}}"#) == nil)
    }

    @Test func fluxCompatibleOpenAI() {
        #expect(OpenAISSE.parse(#"data: {"choices":[{"delta":{"content":"Salut"}}]}"#) == .text("Salut"))
        #expect(OpenAISSE.parse("data: [DONE]") == .stop(nil))
        #expect(OpenAISSE.parse(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == .stop("stop"))
    }

    @Test func corpsDeRequeteClaudeAvecRepli() throws {
        let messages = [ChatMessage(role: .user, text: "Bonjour")]
        let opus = AIClient.claudeBody(model: "claude-opus-5-5", messages: messages)
        #expect(opus["fallbacks"] as? String == "default")
        #expect(opus["stream"] as? Bool == true)
        #expect(opus["thinking"] == nil, "réflexion adaptative par défaut : paramètre omis")
        let haiku = AIClient.claudeBody(model: "claude-haiku-4-5", messages: messages)
        #expect(haiku["fallbacks"] == nil)

        let request = try AIClient.makeChatRequest(provider: .claude, baseURL: "", apiKey: "cle", model: "claude-opus-5-5", messages: messages)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test func cleManquante() {
        #expect(throws: AIError.self) {
            try AIClient.makeChatRequest(provider: .claude, baseURL: "", apiKey: nil, model: "claude-opus-5-5", messages: [])
        }
    }

    @Test func messageDErreurDeLAPI() {
        #expect(AIClient.errorMessage(from: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#) == "invalid x-api-key")
    }
}
