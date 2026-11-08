import Foundation
import Testing
@testable import Notchkit

struct AgentHookTranslatorTests {
    @Test func codexGardeLesEvenementsDeClaudeAvecUneSessionPrefixee() throws {
        let events = AgentHookTranslator.events(from: [
            "hook_event_name": "PreToolUse", "session_id": "thr_1", "cwd": "/work/api",
            "tool_name": "Bash", "tool_input": ["command": "npm test"],
        ], agent: .codex)
        let first = try #require(events.first)
        let event = try #require(ClaudeHookEvent(json: first))
        #expect(event.kind == .preToolUse)
        #expect(event.sessionID == "codex:thr_1")
        #expect(event.toolSummary["command"] == "npm test")
        #expect(CodingAgent.of(sessionID: event.sessionID) == .codex)
    }

    @Test func correctifDeCodexDevientUneModification() {
        let patch = """
        *** Begin Patch
        *** Update File: Sources/App.swift
        @@
        -let title = "Old"
        +let title = "New"
        *** End Patch
        """
        let (tool, input) = AgentHookTranslator.patchEdit(patch)
        #expect(tool == "Edit")
        #expect(input["file_path"] as? String == "Sources/App.swift")
        #expect(input["old_string"] as? String == "let title = \"Old\"")
        #expect(input["new_string"] as? String == "let title = \"New\"")

        let (newTool, newInput) = AgentHookTranslator.patchEdit("*** Add File: notes.md\n+# Notes\n")
        #expect(newTool == "Write")
        #expect(newInput["content"] as? String == "# Notes")
    }

    @Test func geminiEstTraduitEnEvenementsDeClaude() throws {
        let tool = AgentHookTranslator.events(from: [
            "hook_event_name": "BeforeTool", "session_id": "s1", "cwd": "/work/site",
            "tool_name": "run_shell_command", "tool_input": ["command": "ls", "description": "List files"],
        ], agent: .gemini)
        let first = try #require(tool.first)
        let event = try #require(ClaudeHookEvent(json: first))
        #expect(event.kind == .preToolUse)
        #expect(event.toolName == "Bash")
        #expect(event.sessionID == "gemini:s1")

        let done = AgentHookTranslator.events(from: ["hook_event_name": "AfterAgent", "session_id": "s1"], agent: .gemini)
        #expect(done.first?["hook_event_name"] as? String == "Stop")

        let ask = AgentHookTranslator.events(from: [
            "hook_event_name": "Notification", "session_id": "s1",
            "notification_type": "ToolPermission", "message": "Allow ls?",
        ], agent: .gemini)
        #expect(ask.first?["notification_type"] as? String == "permission_prompt")
        // Événements sans équivalent : ignorés.
        #expect(AgentHookTranslator.events(from: ["hook_event_name": "BeforeModel", "session_id": "s1"], agent: .gemini).isEmpty)
    }

    @Test func commandeDeCursorDonneUneEtapePuisSaSortie() throws {
        let events = AgentHookTranslator.events(from: [
            "hook_event_name": "afterShellExecution", "conversation_id": "c1",
            "workspace_roots": ["/work/app"], "command": "npm run build", "output": "done",
        ], agent: .cursor)
        #expect(events.count == 2)
        let post = try #require(ClaudeHookEvent(json: events[1]))
        #expect(post.kind == .postToolUse)
        #expect(post.command?.output == ["done"])
        #expect(post.sessionID == "cursor:c1")
        #expect(post.cwd == "/work/app")
        // Les outils déjà suivis par leurs propres hooks ne sont pas comptés deux fois.
        #expect(AgentHookTranslator.events(from: ["hook_event_name": "postToolUse", "conversation_id": "c1",
                                                  "tool_name": "Shell"], agent: .cursor).isEmpty)
    }

    @Test func reponsesTraduitesPourChaqueAgent() {
        let followUp: [String: Any] = ["decision": "block", "reason": "Also update the README"]
        let cursorStop = AgentHookTranslator.response(followUp, to: ["hook_event_name": "stop"], agent: .cursor)
        #expect(cursorStop["followup_message"] as? String == "Also update the README")
        #expect(AgentHookTranslator.response(nil, to: ["hook_event_name": "beforeSubmitPrompt"], agent: .cursor)["continue"] as? Bool == true)

        let geminiStop = AgentHookTranslator.response(followUp, to: ["hook_event_name": "AfterAgent"], agent: .gemini)
        #expect(geminiStop["decision"] as? String == "deny")
        // Rien à dire : un objet vide, jamais une sortie vide (Gemini CLI et Cursor attendent du JSON).
        #expect(AgentHookTranslator.response(nil, to: ["hook_event_name": "BeforeTool"], agent: .gemini).isEmpty)

        let allow: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]]
        let codex = AgentHookTranslator.response(allow, to: ["hook_event_name": "PermissionRequest"], agent: .codex)
        #expect(((codex["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"] as? String == "allow")
    }

    @Test func messagesRemisSeulementQuandLAgentPeutLesRecevoir() {
        #expect(AgentHookTranslator.acceptsMessages(.codex, claudeEvent: "UserPromptSubmit"))
        #expect(AgentHookTranslator.acceptsMessages(.cursor, claudeEvent: "Stop"))
        #expect(!AgentHookTranslator.acceptsMessages(.cursor, claudeEvent: "PostToolUse"))
        #expect(!AgentHookTranslator.acceptsMessages(.gemini, claudeEvent: "UserPromptSubmit"))
    }
}

struct AgentHooksInstallerTests {
    @Test func installationGardeLesHooksDeLUtilisateur() throws {
        let mine: [String: Any] = ["hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-policy.sh"]]]]]]
        let installed = AgentHooksInstaller.installing(into: mine, agent: .codex)
        let groups = try #require((installed["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        #expect(groups.count == 2)
        #expect(AgentHooksInstaller.isInstalled(in: installed, agent: .codex))

        let removed = AgentHooksInstaller.removing(from: installed)
        #expect(NSDictionary(dictionary: removed).isEqual(to: mine))
        #expect(!AgentHooksInstaller.hasOurHooks(in: removed))
    }

    @Test func seulCodexAttendLaDecisionDeLEncoche() throws {
        let hooks = try #require(AgentHooksInstaller.installing(into: [:], agent: .codex)["hooks"] as? [String: Any])
        let permission = try #require(((hooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        #expect((permission["command"] as? String)?.hasSuffix(" codex 1") == true)
        #expect(permission["timeout"] as? Int == AgentHooksInstaller.decisionTimeout)
        let stop = try #require(((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        #expect((stop["command"] as? String)?.hasSuffix(" codex 0") == true)
    }

    @Test func formatsDeGeminiEtDeCursor() throws {
        let gemini = try #require(AgentHooksInstaller.installing(into: [:], agent: .gemini)["hooks"] as? [String: Any])
        let beforeTool = try #require((gemini["BeforeTool"] as? [[String: Any]])?.first)
        #expect(beforeTool["matcher"] as? String == "*")
        // Délai de Gemini CLI en millisecondes.
        #expect(((beforeTool["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int) == AgentHooksInstaller.eventTimeout * 1000)

        let cursor = AgentHooksInstaller.installing(into: [:], agent: .cursor)
        #expect(cursor["version"] as? Int == 1)
        let stop = try #require(((cursor["hooks"] as? [String: Any])?["stop"] as? [[String: Any]])?.first)
        #expect((stop["command"] as? String)?.contains(AgentHooksInstaller.scriptName) == true)
        #expect(AgentHooksInstaller.removing(from: cursor)["hooks"] == nil)
    }

    @Test func scriptRenvoieToujoursDuJSON() {
        let script = AgentHooksInstaller.script(port: 52_731, token: "abc")
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("http://127.0.0.1:52731\(AgentHookTranslator.path)"))
        #expect(script.contains("X-Notchkit-Token: abc"))
        #expect(script.contains("printf '{}\\n'"))
    }
}
