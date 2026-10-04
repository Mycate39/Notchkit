import Foundation
import Testing
@testable import Notchkit

struct HTTPParserTests {
    func request(_ body: String, token: String = "abc") -> Data {
        Data("POST /notchkit/claude/hook HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Notchkit-Token: \(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    }

    @Test func requeteComplete() throws {
        guard case let .complete(parsed) = HTTPParser.parse(request(#"{"a":1}"#)) else {
            Issue.record("requête non reconnue"); return
        }
        #expect(parsed.method == "POST")
        #expect(parsed.path == "/notchkit/claude/hook")
        #expect(parsed.headers["x-notchkit-token"] == "abc")
        #expect(String(data: parsed.body, encoding: .utf8) == #"{"a":1}"#)
    }

    @Test func requeteIncompleteTantQueLeCorpsNestPasArrive() {
        let full = request(#"{"hook_event_name":"Stop"}"#)
        guard case .incomplete = HTTPParser.parse(full.prefix(full.count - 5)) else {
            Issue.record("devrait attendre la suite"); return
        }
    }

    @Test func reponseJSON() {
        let response = String(data: HTTPParser.response(status: 200, json: ["decision": "block"]), encoding: .utf8) ?? ""
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Content-Type: application/json"))
        #expect(response.hasSuffix(#"{"decision":"block"}"#))
    }
}

struct ClaudeHooksInstallerTests {
    let existing: [String: Any] = [
        "model": "opus",
        "hooks": [
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "echo perso"]]]],
        ],
    ]

    @Test func installationConserveLesReglagesExistants() throws {
        let installed = ClaudeHooksInstaller.installing(into: existing, port: 52731, token: "t")
        #expect(installed["model"] as? String == "opus")
        let hooks = try #require(installed["hooks"] as? [String: Any])
        let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(pre.count == 2, "le hook personnel doit être conservé")
        #expect(ClaudeHooksInstaller.isInstalled(in: installed, port: 52731, token: "t"))
        #expect(!ClaudeHooksInstaller.isInstalled(in: installed, port: 52731, token: "autre"))
    }

    @Test func reinstallerNeDupliquePas() throws {
        let twice = ClaudeHooksInstaller.installing(
            into: ClaudeHooksInstaller.installing(into: existing, port: 52731, token: "t"),
            port: 52731, token: "t"
        )
        let hooks = try #require(twice["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [[String: Any]])?.count == 1)
        #expect((hooks["PreToolUse"] as? [[String: Any]])?.count == 2)
    }

    @Test func desinstallationRetrouveLEtatInitial() throws {
        let removed = ClaudeHooksInstaller.removing(from: ClaudeHooksInstaller.installing(into: existing, port: 52731, token: "t"))
        let hooks = try #require(removed["hooks"] as? [String: Any])
        #expect(hooks.keys.sorted() == ["PreToolUse"])
        #expect(removed["model"] as? String == "opus")

        // Sans hooks personnels, la clé « hooks » disparaît complètement.
        let clean = ClaudeHooksInstaller.removing(from: ClaudeHooksInstaller.installing(into: [:], port: 52731, token: "t"))
        #expect(clean["hooks"] == nil)
    }
}

struct ClaudeActivityTests {
    func event(_ name: String, session: String = "s1", extra: [String: Any] = [:]) -> ClaudeHookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/Users/moi/Notchkit"]
        json.merge(extra) { $1 }
        return ClaudeHookEvent(json: json)!
    }

    @Test func cycleDeTravail() throws {
        var tracker = ClaudeActivityTracker()
        tracker.apply(event("UserPromptSubmit", extra: ["prompt": "Ajoute un bouton"]))
        tracker.apply(event("PreToolUse", extra: ["tool_name": "Edit", "tool_input": ["file_path": "/a/b/Vue.swift", "old_string": "…"]]))

        let working = try #require(tracker.displayedSession)
        #expect(working.state == .working)
        #expect(working.projectName == "Notchkit")
        #expect(working.prompt == "Ajoute un bouton")
        #expect(working.currentAction?.text.contains("Vue.swift") == true)
        #expect(working.currentAction?.symbol == "pencil")

        #expect(tracker.apply(event("Notification", extra: ["notification_type": "permission_prompt", "message": "Autoriser Bash ?"])) == .needsPermission)
        #expect(tracker.displayedSession?.attentionMessage == "Autoriser Bash ?")

        #expect(tracker.apply(event("Stop")) == .finished)
        #expect(tracker.displayedSession?.state == .finished)
        #expect(!tracker.hasActiveSession)
    }

    @Test func sessionSansNouvellesConsidereeTerminee() {
        var tracker = ClaudeActivityTracker()
        let start = Date(timeIntervalSince1970: 0)
        tracker.apply(event("UserPromptSubmit"), at: start)
        tracker.expireStaleSessions(at: start.addingTimeInterval(11 * 60))
        #expect(tracker.displayedSession?.state == .finished)
    }

    @Test func finDeSessionLaRetire() {
        var tracker = ClaudeActivityTracker()
        tracker.apply(event("UserPromptSubmit"))
        tracker.apply(event("SessionEnd"))
        #expect(tracker.displayedSession == nil)
    }

    @Test func descriptionDesOutils() {
        #expect(ClaudeToolDescriber.describe(toolName: "Bash", summary: ["command": "xcodebuild test", "description": "Lance les tests"]).text.contains("Lance les tests"))
        #expect(ClaudeToolDescriber.describe(toolName: "Grep", summary: ["pattern": "TODO"]).symbol == "magnifyingglass")
        #expect(ClaudeToolDescriber.describe(toolName: "mcp__github__create_issue", summary: [:]).text.contains("github"))
    }
}

struct ClaudeUsageTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3600 + minute * 60))
    }

    @Test func sessionsDeCinqHeures() {
        let entries = [
            ClaudeUsageEntry(date: date(10, 20), tokens: 100),
            ClaudeUsageEntry(date: date(12, 0), tokens: 50),
            ClaudeUsageEntry(date: date(15, 30), tokens: 10), // après 15:00 → nouvelle session
        ]
        let blocks = ClaudeUsageCalculator.blocks(from: entries, calendar: calendar)
        #expect(blocks.count == 2)
        #expect(blocks[0].start == date(10))
        #expect(blocks[0].tokens == 150)
        #expect(blocks[1].start == date(15))
    }

    @Test func resumeDeLaSessionEnCours() {
        let entries = [
            ClaudeUsageEntry(date: date(1), tokens: 900),
            ClaudeUsageEntry(date: date(10, 20), tokens: 300),
        ]
        let summary = ClaudeUsageCalculator.summary(from: entries, storedMax: 0, now: date(11))
        #expect(summary.currentTokens == 300)
        #expect(summary.personalMax == 900)
        #expect(summary.resetAt != nil)

        let later = ClaudeUsageCalculator.summary(from: entries, storedMax: 0, now: date(20))
        #expect(later.currentTokens == 0)
        #expect(later.resetAt == nil)
    }

    @Test func lectureLigneDeTranscription() throws {
        let line = #"{"type":"assistant","timestamp":"2026-10-03T20:55:49.044Z","requestId":"req_1","message":{"id":"msg_1","usage":{"input_tokens":2,"cache_creation_input_tokens":13586,"cache_read_input_tokens":21174,"output_tokens":233}}}"#
        let parsed = try #require(ClaudeUsageCalculator.parse(line: Data(line.utf8)))
        #expect(parsed.entry.tokens == 2 + 233 + 13586)
        #expect(parsed.id == "msg_1|req_1")
        #expect(ClaudeUsageCalculator.parse(line: Data(#"{"type":"user"}"#.utf8)) == nil)
    }
}

@MainActor
struct ClaudeMessageDeliveryTests {
    func makeModule() -> ClaudeModule {
        ClaudeModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
    }

    @Test func messageRemisALaProchaineAction() throws {
        let module = makeModule()
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s", "prompt": "Travaille"])
        module.send("Utilise plutôt une liste")

        let response = try #require(module.handle(["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Read"]))
        let output = try #require(response["hookSpecificOutput"] as? [String: Any])
        #expect(output["hookEventName"] as? String == "PostToolUse")
        #expect((output["additionalContext"] as? String)?.contains("Utilise plutôt une liste") == true)

        // Une fois remis, le message n'est plus renvoyé.
        #expect(module.handle(["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Read"]) == nil)
    }

    @Test func messageAuMomentDeLArretRelanceClaude() throws {
        let module = makeModule()
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s"])
        module.send("Ajoute aussi des tests")

        let response = try #require(module.handle(["hook_event_name": "Stop", "session_id": "s"]))
        #expect(response["decision"] as? String == "block")
        #expect((response["reason"] as? String)?.contains("Ajoute aussi des tests") == true)
        #expect(module.displayedSession?.state == .working)
    }

    @Test func messageVidesOuSansSessionIgnores() {
        let module = makeModule()
        module.send("Personne pour le recevoir")
        #expect(module.pendingMessages.isEmpty)
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s"])
        module.send("   ")
        #expect(module.pendingMessages.isEmpty)
    }
}
