import Foundation
import Observation

/// Gestionnaire central des modules.
///
/// - instancie et démarre uniquement les modules activés (et débloqués) ;
/// - arrête et libère les modules désactivés ;
/// - détermine quel module occupe l'affichage compact selon les priorités.
@MainActor
@Observable
final class ModuleManager {
    /// Modules actuellement chargés, dans l'ordre choisi par l'utilisateur.
    private(set) var activeModules: [any NotchModule] = []

    /// Reçoit les alertes émises par les modules (branché sur le `NotchViewModel`).
    @ObservationIgnored var alertHandler: (@MainActor (NotchAlert) -> Void)?
    /// Ouvre les réglages (branché sur l'AppDelegate).
    @ObservationIgnored var settingsHandler: (@MainActor () -> Void)?

    @ObservationIgnored let availableModules: [any NotchModule.Type]
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let entitlements: EntitlementManager
    @ObservationIgnored private var instances: [String: any NotchModule] = [:]

    init(
        settings: SettingsStore,
        entitlements: EntitlementManager,
        availableModules: [any NotchModule.Type] = ModuleRegistry.allModules
    ) {
        self.settings = settings
        self.entitlements = entitlements
        self.availableModules = availableModules
    }

    // MARK: - Consultation

    /// Descripteurs de tous les modules, triés selon l'ordre de l'utilisateur.
    var orderedDescriptors: [ModuleDescriptor] {
        orderedTypes.map { $0.descriptor }
    }

    func isEnabled(_ id: String) -> Bool {
        if let stored = settings.settings.moduleEnabled[id] { return stored }
        return availableModules.first { $0.descriptor.id == id }?.descriptor.defaultEnabled ?? false
    }

    func isUnlocked(_ descriptor: ModuleDescriptor) -> Bool {
        entitlements.isUnlocked(descriptor)
    }

    /// Instance chargée d'un module, ou `nil` s'il est désactivé.
    func module(for id: String) -> (any NotchModule)? {
        activeModules.first { $0.moduleID == id }
    }

    /// Module à afficher quand l'encoche est repliée : priorité la plus haute,
    /// puis ordre de l'utilisateur en cas d'égalité.
    var compactModule: (any NotchModule)? {
        var best: (any NotchModule)?
        for module in activeModules where module.compactPriority > (best?.compactPriority ?? .none) {
            best = module
        }
        return best
    }

    // MARK: - Modification

    func setEnabled(_ enabled: Bool, for id: String) {
        settings.settings.moduleEnabled[id] = enabled
        reload()
    }

    /// Synchronise les modules chargés avec les réglages : démarre ceux qui
    /// viennent d'être activés, arrête ceux qui viennent d'être désactivés.
    func reload() {
        var loaded: [any NotchModule] = []
        for type in orderedTypes {
            let descriptor = type.descriptor
            let shouldRun = isEnabled(descriptor.id) && entitlements.isUnlocked(descriptor)

            if shouldRun {
                if let existing = instances[descriptor.id] {
                    loaded.append(existing)
                } else {
                    let module = type.init(context: makeContext())
                    instances[descriptor.id] = module
                    module.start()
                    loaded.append(module)
                }
            } else if let module = instances.removeValue(forKey: descriptor.id) {
                module.stop()
            }
        }
        activeModules = loaded
    }

    /// Arrête tous les modules (à la fermeture de l'app).
    func stopAll() {
        instances.values.forEach { $0.stop() }
        instances.removeAll()
        activeModules = []
    }

    // MARK: - Privé

    private var orderedTypes: [any NotchModule.Type] {
        let order = settings.settings.moduleOrder
        // Les modules absents de l'ordre sauvegardé (ex. nouveaux modules) viennent à la fin,
        // dans l'ordre du registre.
        return availableModules.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.element.descriptor.id) ?? order.count + lhs.offset
            let r = order.firstIndex(of: rhs.element.descriptor.id) ?? order.count + rhs.offset
            return l < r
        }.map(\.element)
    }

    private func makeContext() -> ModuleContext {
        ModuleContext(
            presentAlert: { [weak self] alert in self?.alertHandler?(alert) },
            openSettings: { [weak self] in self?.settingsHandler?() }
        )
    }
}
