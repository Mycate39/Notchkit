import Foundation
import Testing
@testable import Notchkit

struct LidAwakeTests {
    private func battery(_ level: Int, plugged: Bool) -> BatteryState {
        BatteryState(level: level, isCharging: plugged, isCharged: false, powerSource: plugged ? .ac : .battery,
                     minutesToEmpty: nil, minutesToFull: nil)
    }

    @Test func batterieSousLeSeuilArreteLeMaintien() {
        let settings = LidAwakeSettings()
        #expect(LidAwakePolicy.safetyStop(battery: battery(19, plugged: false), thermal: .nominal, lidClosed: true,
                                          settings: settings) == .battery(19))
        #expect(LidAwakePolicy.safetyStop(battery: battery(40, plugged: false), thermal: .nominal, lidClosed: true,
                                          settings: settings) == nil)
        // Branché, la batterie basse n'arrête rien.
        #expect(LidAwakePolicy.safetyStop(battery: battery(5, plugged: true), thermal: .nominal, lidClosed: true,
                                          settings: settings) == nil)
    }

    @Test func chaleurNArreteQueCapotFerme() {
        let settings = LidAwakeSettings()
        #expect(LidAwakePolicy.safetyStop(battery: nil, thermal: .serious, lidClosed: true, settings: settings) == .heat)
        #expect(LidAwakePolicy.safetyStop(battery: nil, thermal: .critical, lidClosed: true, settings: settings) == .heat)
        #expect(LidAwakePolicy.safetyStop(battery: nil, thermal: .serious, lidClosed: false, settings: settings) == nil)
        #expect(LidAwakePolicy.safetyStop(battery: nil, thermal: .fair, lidClosed: true, settings: settings) == nil)
    }

    @Test func debranchementSeulementSiDemande() {
        var settings = LidAwakeSettings()
        #expect(LidAwakePolicy.safetyStop(battery: battery(80, plugged: false), thermal: .nominal, lidClosed: true,
                                          settings: settings) == nil)
        settings.stopsWhenUnplugged = true
        #expect(LidAwakePolicy.safetyStop(battery: battery(80, plugged: false), thermal: .nominal, lidClosed: true,
                                          settings: settings) == .unplugged)
    }

    @Test func agentsGardentLeMacEveillePendantLeDelaiCalme() {
        var settings = LidAwakeSettings()
        settings.agentQuietMinutes = 3
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(LidAwakePolicy.agentsHold(working: true, lastActivity: nil, now: now, settings: settings))
        #expect(LidAwakePolicy.agentsHold(working: false, lastActivity: now.addingTimeInterval(-120), now: now, settings: settings))
        #expect(!LidAwakePolicy.agentsHold(working: false, lastActivity: now.addingTimeInterval(-200), now: now, settings: settings))
        settings.followsAgents = false
        #expect(!LidAwakePolicy.agentsHold(working: true, lastActivity: now, now: now, settings: settings))
    }

    @Test func dureeEcoulee() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(!LidAwakePolicy.timerExpired(until: nil, now: now))
        #expect(LidAwakePolicy.timerExpired(until: now, now: now))
        #expect(!LidAwakePolicy.timerExpired(until: now.addingTimeInterval(60), now: now))
    }

    @Test func commandeAwakeLue() throws {
        let run = try #require(ScriptRequest(fields: ["action": "start", "id": "run-1", "awake": "1"]))
        #expect(run.keepsAwake)
        let awake = try #require(ScriptRequest(fields: ["action": "awake", "value": "90"]))
        #expect(awake.action == .awake)
        #expect(awake.value == "90")
        #expect(!(try #require(ScriptRequest(fields: ["action": "start", "id": "x"]))).keepsAwake)
    }

    @Test func commandeNotchkitConnaitAwake() {
        let script = ScriptCommandInstaller.script(port: 1, token: "t")
        #expect(script.contains("--awake) awake=1; shift ;;"))
        #expect(script.contains("post action=awake"))
    }
}

struct AwakeHelperInstallTests {
    @Test @MainActor func scriptDInstallationProtegeLesChemins() {
        let script = AwakeHelperClient.installScript(bundledHelper: "/Applications/Note's Kit.app/Contents/MacOS/NotchkitAwakeHelper",
                                                     plist: "/tmp/x.plist")
        // L'apostrophe d'un chemin est échappée, et le démon est bien déclaré au système.
        #expect(script.contains("'/Applications/Note'\\''s Kit.app/Contents/MacOS/NotchkitAwakeHelper'"))
        #expect(script.contains("/bin/launchctl bootstrap system '/Library/LaunchDaemons/\(AwakeHelper.plistName)'"))
        #expect(script.contains("/usr/sbin/chown root:wheel '/Library/PrivilegedHelperTools/\(AwakeHelper.label)'"))
    }

    @Test @MainActor func desinstallationRetablitLaVeille() {
        #expect(AwakeHelperClient.uninstallScript.contains("/usr/bin/pmset -a disablesleep 0"))
    }

    @Test @MainActor func declarationLaunchdLanceLAssistantALaDemande() throws {
        let plist = AwakeHelperClient.launchdPlist
        #expect(plist["Label"] as? String == AwakeHelper.label)
        let machServices = try #require(plist["MachServices"] as? [String: Bool])
        #expect(machServices[AwakeHelper.label] == true)
    }
}
