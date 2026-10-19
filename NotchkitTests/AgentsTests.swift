import Foundation
import Testing
@testable import Notchkit

/// Module Agents et widgets pleine page.
struct AgentsTests {
    @Test func widgetPleinePageSeulSurSaPage() {
        // Le widget pleine page sépare sa page en trois : avant lui, lui seul, après lui.
        let pages = WidgetLayoutEngine.isolate(["agents"], in: [["music", "agents", "clock"], ["weather"]])
        #expect(pages == [["music"], ["agents"], ["clock"], ["weather"]])
        // Déjà seul, ou absent : rien ne change.
        #expect(WidgetLayoutEngine.isolate(["agents"], in: [["agents"], ["clock"]]) == [["agents"], ["clock"]])
        #expect(WidgetLayoutEngine.isolate([], in: [["music", "clock"]]) == [["music", "clock"]])
    }

    @Test func paginationAutomatiqueIsoleLeWidgetPleinePage() {
        let pages = WidgetLayoutEngine.pages(activeIDs: ["music", "agents", "clock"],
                                             weights: ["music": 1, "agents": 4, "clock": 1],
                                             layout: nil, capacity: 4, fullPage: ["agents"])
        #expect(pages.contains(["agents"]))
        #expect(pages.flatMap { $0 }.sorted() == ["agents", "clock", "music"])
    }

    @Test func humeurDeLaMascotteSelonLaSession() {
        var session = ClaudeSession(id: "a", state: .working, lastEventAt: Date())
        #expect(AgentsModule.mood(for: session, celebrating: false) == .working)
        session.state = .waitingForPermission
        #expect(AgentsModule.mood(for: session, celebrating: true) == .waiting)
        session.state = .finished
        #expect(AgentsModule.mood(for: session, celebrating: true) == .happy)
        #expect(AgentsModule.mood(for: session, celebrating: false) == .idle)
        #expect(AgentsModule.mood(for: nil, celebrating: false) == .idle)
    }
}

/// Modifications, commandes et étapes lues dans les événements de Claude Code.
struct AgentsLiveTests {
    @Test func modificationLueDansLEvenement() throws {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Edit",
            "tool_input": ["file_path": "/tmp/projet/invoice.ts", "old_string": "const TVA = 0.196", "new_string": "const TVA = 0.20\n// 2026"],
        ]
        let event = try #require(ClaudeHookEvent(json: json))
        let edit = try #require(event.edit)
        #expect(edit.fileName == "invoice.ts")
        #expect(edit.removed == ["const TVA = 0.196"])
        #expect(edit.added == ["const TVA = 0.20", "// 2026"])
    }

    @Test func numeroDeLigneRetrouveDansLeFichier() {
        let contents = "import x\n\nconst TVA = 0.196\nexport"
        #expect(ClaudeEdit.lineNumber(of: "const TVA = 0.196", in: contents) == 3)
        #expect(ClaudeEdit.lineNumber(of: "absent", in: contents) == nil)
        let edit = ClaudeEdit(toolName: "Edit", input: ["file_path": "/x.ts", "old_string": "const TVA = 0.196", "new_string": "y"],
                              fileContents: { _ in contents })
        #expect(edit?.firstLine == 3)
    }

    @Test func commandeEtFinDeSaSortie() throws {
        let output = (1...10).map { "ligne \($0)" }.joined(separator: "\n")
        let json: [String: Any] = [
            "hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash",
            "tool_input": ["command": "npm test"], "tool_response": ["stdout": output, "stderr": ""],
        ]
        let command = try #require(ClaudeHookEvent(json: json)?.command)
        #expect(command.command == "npm test")
        #expect(command.output.count == ClaudeCommand.maxOutputLines)
        #expect(command.output.last == "ligne 10")
    }

    @Test func etapesFranchiesPuisRemisesAZero() throws {
        var tracker = ClaudeActivityTracker()
        func send(_ name: String, tool: String? = nil) {
            var json: [String: Any] = ["hook_event_name": name, "session_id": "s"]
            if let tool { json["tool_name"] = tool; json["tool_input"] = ["file_path": "/a.swift", "command": "ls"] }
            if let event = ClaudeHookEvent(json: json) { tracker.apply(event) }
        }
        send("UserPromptSubmit")
        send("PreToolUse", tool: "Read")
        send("PreToolUse", tool: "Bash")
        var session = try #require(tracker.sessions["s"])
        #expect(session.phases == [.read, .run])
        #expect(session.currentPhase == .run)
        send("Stop")
        session = try #require(tracker.sessions["s"])
        #expect(session.currentPhase == nil)
        send("UserPromptSubmit")
        #expect(tracker.sessions["s"]?.phases.isEmpty == true)
    }

    @Test func frappeLigneParLigne() {
        #expect(AgentEditorPanel.visibleCounts(lengths: [5, 3], typed: 0) == [0, 0])
        #expect(AgentEditorPanel.visibleCounts(lengths: [5, 3], typed: 6) == [5, 1])
        #expect(AgentEditorPanel.visibleCounts(lengths: [5, 3], typed: 100) == [5, 3])
    }
}

/// Autoriser, refuser et répondre aux questions depuis l'encoche.
@MainActor
struct AgentsDecisionTests {
    /// Module Claude dont le contexte voit une page Agents active (sinon rien n'est retenu).
    private func makeModule(withAgents: Bool = true) -> ClaudeModule {
        let base = ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in })
        let agents = AgentsModule(context: base)
        var context = base
        context.otherModule = { id in withAgents && id == "agents" ? agents : nil }
        return ClaudeModule(context: context)
    }

    private let permission: [String: Any] = [
        "hook_event_name": "PermissionRequest", "session_id": "s", "tool_name": "Bash",
        "tool_input": ["command": "rm -rf node_modules"],
        "permission_suggestions": [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "rm -rf node_modules"]],
                                    "behavior": "allow", "destination": "localSettings"]],
        ClaudeHookServer.waitKey: true,
    ]

    @Test func permissionRetenuePuisAutoriseePourToujours() throws {
        let module = makeModule()
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s"])
        var response: [String: Any]??
        module.handle(permission, reply: HookReply { response = .some($0) })
        // Rien n'est répondu tant que l'utilisateur n'a pas décidé.
        #expect(response == nil)
        let prompt = try #require(module.tracker.sessions["s"]?.permissionPrompt)
        #expect(prompt.canAlwaysAllow)
        #expect(module.tracker.sessions["s"]?.state == .waitingForPermission)

        module.decidePermission("s", allow: true, always: true)
        let output = try #require(response??["hookSpecificOutput"] as? [String: Any])
        let decision = try #require(output["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        #expect((decision["updatedPermissions"] as? [[String: Any]])?.first?["type"] as? String == "addRules")
        #expect(module.tracker.sessions["s"]?.permissionPrompt == nil)
        #expect(module.tracker.sessions["s"]?.state == .working)
    }

    @Test func permissionRefusee() throws {
        let module = makeModule()
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s"])
        var response: [String: Any]?
        module.handle(permission, reply: HookReply { response = $0 })
        module.decidePermission("s", allow: false)
        let decision = try #require((response?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "deny")
    }

    @Test func sansPageAgentsLeTerminalDemande() {
        let module = makeModule(withAgents: false)
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s"])
        var answered = false
        module.handle(permission, reply: HookReply { _ in answered = true })
        #expect(answered)
        #expect(module.tracker.sessions["s"]?.permissionPrompt == nil)
    }

    @Test func questionsReponduesDepuisLEncoche() throws {
        let module = makeModule()
        _ = module.handle(["hook_event_name": "UserPromptSubmit", "session_id": "s"])
        let input: [String: Any] = ["questions": [[
            "question": "Quel framework ?", "header": "Framework", "multiSelect": false,
            "options": [["label": "React", "description": "Composants"], ["label": "Vue"]],
        ]]]
        var response: [String: Any]?
        module.handle(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "AskUserQuestion",
                       "tool_input": input, ClaudeHookServer.waitKey: true], reply: HookReply { response = $0 })
        let prompt = try #require(module.tracker.sessions["s"]?.questionPrompt)
        #expect(prompt.questions.first?.options.map(\.label) == ["React", "Vue"])

        module.answerQuestions("s", selections: ["Quel framework ?": ["React"]])
        let output = try #require(response?["hookSpecificOutput"] as? [String: Any])
        #expect(output["permissionDecision"] as? String == "allow")
        let updated = try #require(output["updatedInput"] as? [String: Any])
        #expect((updated["answers"] as? [String: String])?["Quel framework ?"] == "React")
        #expect(updated["questions"] != nil)
    }

    @Test func reponsesMultiplesSepareesParDesVirgules() {
        #expect(ClaudeQuestionPrompt.answers(["Q": ["A", "B"]]) == ["Q": "A, B"])
    }
}
