import SwiftUI
import Observation

/// Module Commandes : la commande `notchkit` affiche dans l'encoche des notifications et des activités
/// envoyées par n'importe quel script (build, tests, déploiement, export…).
///
/// Elle parle à un petit serveur local (127.0.0.1 seulement, jeton secret), comme les hooks des agents.
@MainActor
@Observable
final class ScriptsModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "scripts",
        name: "Commandes",
        summary: "La commande notchkit affiche dans l'encoche ce que font vos scripts : une notification, ou une activité en cours (build, tests, export) jusqu'à sa fin.",
        systemImage: "terminal",
        category: .productivity,
        tier: .free,
        defaultEnabled: true,
        providesWidget: false
    )

    static let defaultPort: UInt16 = 52_732

    private(set) var tracker = ScriptActivityTracker()
    private(set) var serverState: ClaudeHookServer.State = .stopped
    private(set) var installStatus: ScriptCommandInstaller.Status = .notInstalled
    private(set) var installerMessage: String?

    let port: UInt16
    @ObservationIgnored private let token: String
    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let server: ClaudeHookServer
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?

    private enum Keys {
        static let token = "module.scripts.token"
        static let port = "module.scripts.port"
    }

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Keys.token) {
            token = stored
        } else {
            let generated = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            defaults.set(generated, forKey: Keys.token)
            token = generated
        }
        let storedPort = defaults.integer(forKey: Keys.port)
        port = (1024...65535).contains(storedPort) ? UInt16(storedPort) : Self.defaultPort
        server = ClaudeHookServer(token: token)
    }

    func start() {
        server.onStateChange = { [weak self] state in self?.serverState = state }
        server.routes[ScriptCommandInstaller.path] = { [weak self] fields, reply in
            self?.receive(fields)
            reply.send(["ok": true])
        }
        server.start(port: port)
        refreshInstallState()
        // Commande installée par une version précédente : réécrite d'elle-même.
        if installStatus == .outdated, !AutomatedRun.isActive { installCommand() }
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.tracker.expireStale()
            }
        }
    }

    func stop() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        server.stop()
    }

    // MARK: Demandes

    func receive(_ fields: [String: Any]) {
        guard let request = ScriptRequest(fields: fields) else { return }
        switch tracker.apply(request) {
        case .none:
            break
        case let .notification(title, message, symbol, colorName):
            context.presentAlert(ScriptAlerts.notification(title: title, message: message, symbol: symbol,
                                                           color: ScriptPalette.color(named: colorName) ?? .cyan))
        case let .finished(title, message, succeeded, duration):
            context.presentAlert(ScriptAlerts.finished(title: title, message: message, succeeded: succeeded, duration: duration))
        }
    }

    // MARK: Installation

    func refreshInstallState() {
        installStatus = ScriptCommandInstaller.status(port: port, token: token)
    }

    func installCommand() {
        do {
            let link = try ScriptCommandInstaller.install(port: port, token: token)
            installerMessage = String(localized: "Commande installée : \(link.path)")
        } catch {
            installerMessage = String(localized: "La commande n'a pas pu être installée : \(error.localizedDescription)")
        }
        refreshInstallState()
    }

    func uninstallCommand() {
        ScriptCommandInstaller.uninstall()
        installerMessage = String(localized: "Commande retirée.")
        refreshInstallState()
    }

    // MARK: Affichage

    /// Activité affichée : la plus récente.
    var displayedActivity: ScriptActivity? { tracker.ordered.first }

    var compactPriority: ModulePriority { displayedActivity == nil ? .none : .normal }

    var keyLineColor: Color? { displayedActivity?.color }

    func compactLeading() -> AnyView? {
        guard let activity = displayedActivity else { return nil }
        return AnyView(ScriptCompactIcon(activity: activity))
    }

    func compactTrailing() -> AnyView? {
        guard let activity = displayedActivity else { return nil }
        return AnyView(ScriptCompactValue(activity: activity, extraCount: tracker.activities.count - 1))
    }

    func expandedView() -> AnyView {
        AnyView(ScriptsExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(ScriptsSettingsView(module: self))
    }
}

#if DEBUG
extension ScriptsModule {
    /// Demande fictive (mode démo, captures), traitée comme si elle venait de la commande.
    func debugReceive(_ fields: [String: Any]) { receive(fields) }
}
#endif
