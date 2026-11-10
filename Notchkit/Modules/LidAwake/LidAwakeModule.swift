import AppKit
import SwiftUI
import Observation

/// Mode capot fermé : garde le MacBook éveillé capot fermé (pour laisser travailler Claude Code, un build, un
/// export…), à la main, tant qu'un agent travaille, ou le temps d'une commande `notchkit run --awake`.
///
/// La veille est coupée par l'assistant système (`AwakeHelperClient`, `pmset disablesleep`), installé une fois
/// avec l'accord de l'utilisateur. Sécurités : seuil de batterie, chaleur capot fermé, débranchement (option),
/// durée ; à la fin, capot fermé, le Mac est endormi. Si Notchkit quitte ou plante, l'assistant rétablit la veille.
@MainActor
@Observable
final class LidAwakeModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "lidawake",
        name: "Capot fermé",
        summary: "Garde le Mac éveillé capot fermé, tant qu'un agent travaille ou à la demande, avec des sécurités de batterie et de chaleur.",
        systemImage: "laptopcomputer",
        category: .system,
        tier: .free,
        defaultEnabled: true,
        providesWidget: false
    )

    /// Intervalle de surveillance (batterie, chaleur, capot, agents).
    static let tick: Duration = .seconds(5)

    private(set) var reasons: Set<LidAwakeReason> = []
    /// Fin du maintien manuel à durée choisie.
    private(set) var manualUntil: Date?
    /// Début du maintien en cours (veille réellement coupée).
    private(set) var holdingSince: Date?
    private(set) var lastStop: LidAwakeStop?
    private(set) var helperState: AwakeHelperClient.State = .notInstalled
    private(set) var lidClosed = false
    private(set) var battery: BatteryState?

    var settings: LidAwakeSettings {
        didSet { saveSettings() }
    }

    var isHolding: Bool { holdingSince != nil }
    var isManualOn: Bool { reasons.contains(.manual) }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let helper = AwakeHelperClient()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastAgentActivity: Date?
    /// Commande envoyée à l'assistant en cours (évite deux envois croisés).
    @ObservationIgnored private var applying = false

    private enum Keys {
        static let floor = "module.lidawake.batteryFloor"
        static let unplug = "module.lidawake.stopsWhenUnplugged"
        static let agents = "module.lidawake.followsAgents"
        static let quiet = "module.lidawake.agentQuietMinutes"
    }

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        // Lecture tolérante : nombre ou texte (valeurs passées en argument de lancement), sinon valeur par défaut.
        var settings = LidAwakeSettings()
        let has = { defaults.object(forKey: $0) != nil }
        if has(Keys.floor), LidAwakeSettings.batteryFloors.contains(defaults.integer(forKey: Keys.floor)) {
            settings.batteryFloor = defaults.integer(forKey: Keys.floor)
        }
        if has(Keys.unplug) { settings.stopsWhenUnplugged = defaults.bool(forKey: Keys.unplug) }
        if has(Keys.agents) { settings.followsAgents = defaults.bool(forKey: Keys.agents) }
        if has(Keys.quiet), LidAwakeSettings.quietDelays.contains(defaults.integer(forKey: Keys.quiet)) {
            settings.agentQuietMinutes = defaults.integer(forKey: Keys.quiet)
        }
        self.settings = settings
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.batteryFloor, forKey: Keys.floor)
        defaults.set(settings.stopsWhenUnplugged, forKey: Keys.unplug)
        defaults.set(settings.followsAgents, forKey: Keys.agents)
        defaults.set(settings.agentQuietMinutes, forKey: Keys.quiet)
    }

    // MARK: Cycle de vie

    func start() {
        helperState = helper.state
        guard !AutomatedRun.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.update()
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        reasons.removeAll()
        if isHolding {
            holdingSince = nil
            Task { [helper] in _ = await helper.setSleepDisabled(false) }
        }
    }

    // MARK: Commandes

    /// Interrupteur : `minutes` = durée, `nil` = jusqu'à l'arrêt.
    func setManual(_ on: Bool, minutes: Int? = nil) {
        if on {
            reasons.insert(.manual)
            manualUntil = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
            lastStop = nil
            prepareHelper()
        } else {
            reasons.remove(.manual)
            manualUntil = nil
        }
        Task { await update() }
    }

    /// Commande `notchkit run --awake` : maintien le temps de la commande.
    func holdForCommand(_ id: String, _ on: Bool) {
        if on {
            reasons.insert(.command(id))
            prepareHelper()
        } else {
            reasons.remove(.command(id))
        }
        Task { await update() }
    }

    /// Installe l'assistant s'il ne l'est pas ; macOS demande alors l'accord dans Réglages Système.
    func prepareHelper() {
        guard helper.state != .ready else { return }
        helperState = helper.install()
        if helperState == .needsApproval {
            context.presentAlert(LidAwakeAlerts.needsApproval())
            helper.openApprovalSettings()
        }
    }

    func openApprovalSettings() { helper.openApprovalSettings() }

    func uninstallHelper() {
        reasons.removeAll()
        Task {
            await update()
            await helper.uninstall()
            helperState = helper.state
        }
    }

    // MARK: Surveillance

    /// Relit capot, batterie, chaleur et agents, puis coupe ou rétablit la veille.
    func update(now: Date = Date()) async {
        helperState = helper.state
        lidClosed = LidState.isClosed()
        battery = BatteryState.current()

        // Agents (Claude Code, Codex, Gemini CLI, Cursor) suivis par la page Agents.
        let working = (context.otherModule(ClaudeModule.descriptor.id) as? ClaudeModule)?.tracker.hasActiveSession ?? false
        if working { lastAgentActivity = now }
        if LidAwakePolicy.agentsHold(working: working, lastActivity: lastAgentActivity, now: now, settings: settings) {
            reasons.insert(.agents)
        } else {
            reasons.remove(.agents)
        }

        if reasons.contains(.manual), LidAwakePolicy.timerExpired(until: manualUntil, now: now) {
            reasons.remove(.manual)
            manualUntil = nil
            lastStop = .timer
        }

        let safety = LidAwakePolicy.safetyStop(battery: battery, thermal: ProcessInfo.processInfo.thermalState,
                                               lidClosed: lidClosed, settings: settings)
        if let safety, isHolding {
            // Arrêt de sécurité : l'interrupteur se coupe (il ne repartira pas tout seul une fois branché).
            lastStop = safety
            reasons.remove(.manual)
            manualUntil = nil
            context.presentAlert(LidAwakeAlerts.stopped(safety))
        }

        let wanted = !reasons.isEmpty && safety == nil && helperState == .ready
        await apply(wanted)
    }

    private func apply(_ wanted: Bool) async {
        guard wanted != isHolding, !applying else { return }
        applying = true
        defer { applying = false }
        if wanted {
            if await helper.setSleepDisabled(true) {
                holdingSince = Date()
            }
        } else {
            _ = await helper.setSleepDisabled(false)
            holdingSince = nil
            // Capot fermé : macOS ne se rendort pas de lui-même, Notchkit l'endort.
            if LidAwakePolicy.sleepsOnRelease(lidClosed: lidClosed) {
                _ = await helper.sleepNow()
            }
        }
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { isHolding ? .normal : .none }

    var keyLineColor: Color? { isHolding ? .mint : nil }

    func compactLeading() -> AnyView? {
        guard isHolding else { return nil }
        return AnyView(
            Image(systemName: "laptopcomputer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.mint)
                .accessibilityLabel(Text("Mac éveillé capot fermé"))
        )
    }

    func compactTrailing() -> AnyView? {
        guard let holdingSince else { return nil }
        return AnyView(LidAwakeCompactValue(since: holdingSince, until: manualUntil))
    }

    func expandedView() -> AnyView {
        AnyView(LidAwakeSettingsView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(LidAwakeSettingsView(module: self))
    }
}

#if DEBUG
extension LidAwakeModule {
    /// Maintien fictif pour les captures et le mode démo (l'assistant n'est pas sollicité).
    func debugSetHolding(_ on: Bool, reasons: Set<LidAwakeReason> = [.agents]) {
        self.reasons = on ? reasons : []
        holdingSince = on ? Date().addingTimeInterval(-754) : nil
    }
}
#endif
