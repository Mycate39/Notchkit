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
    @ObservationIgnored var settingsHandler: (@MainActor (String?) -> Void)?
    /// Garde l'encoche dépliée (branché sur le `NotchViewModel`).
    @ObservationIgnored var holdHandler: (@MainActor (Bool) -> Void)?
    /// Retire une alerte (branché sur le `NotchViewModel`).
    @ObservationIgnored var dismissAlertHandler: (@MainActor (UUID) -> Void)?
    /// Bloque l'ouverture au survol (branché sur le `NotchViewModel`).
    @ObservationIgnored var blockExpansionHandler: (@MainActor (Bool) -> Void)?

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

    // MARK: - Disposition des widgets

    /// Taille d'un widget : celle choisie par l'utilisateur, sinon celle du module.
    func size(for id: String) -> WidgetSize {
        if let chosen = settings.settings.widgetLayout?.sizes[id] { return chosen }
        let module = activeModules.first { $0.moduleID == id }
        return WidgetSize(weight: module?.expandedWidthWeight ?? defaultWeight(for: id))
    }

    func weight(for id: String) -> CGFloat { size(for: id).weight }

    private func defaultWeight(for id: String) -> CGFloat {
        // Module inactif : taille par défaut inconnue sans l'instancier, on prend « moyen ».
        1.5
    }

    /// Modules actifs qui ont une carte dans l'encoche dépliée.
    private var widgetModules: [any NotchModule] {
        activeModules.filter { type(of: $0).descriptor.providesWidget }
    }

    private var activeWeights: [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: widgetModules.map { ($0.moduleID, weight(for: $0.moduleID)) })
    }

    /// Pages affichées dans l'encoche dépliée (identifiants des modules actifs).
    var pageIDs: [[String]] {
        WidgetLayoutEngine.pages(
            activeIDs: widgetModules.map(\.moduleID),
            weights: activeWeights,
            layout: settings.settings.widgetLayout
        )
    }

    /// Disposition affichée, figée pour être modifiée.
    private var editableLayout: WidgetLayout {
        WidgetLayoutEngine.materialize(
            activeIDs: widgetModules.map(\.moduleID),
            weights: activeWeights,
            layout: settings.settings.widgetLayout
        )
    }

    func setSize(_ size: WidgetSize, for id: String) {
        var layout = editableLayout
        layout.sizes[id] = size
        settings.settings.widgetLayout = layout
    }

    func move(_ id: String, toPage page: Int, index: Int) {
        settings.settings.widgetLayout = WidgetLayoutEngine.move(id, toPage: page, index: index, in: editableLayout)
    }

    /// Position actuelle d'un widget (page, rang).
    func position(of id: String) -> (page: Int, index: Int)? {
        for (page, ids) in pageIDs.enumerated() {
            if let index = ids.firstIndex(of: id) { return (page, index) }
        }
        return nil
    }

    func usedCapacity(ofPage page: [String]) -> CGFloat {
        WidgetLayoutEngine.usedCapacity(of: page, weights: activeWeights)
    }

    /// Réglages avant la dernière disposition prête à l'emploi (pour pouvoir annuler).
    private(set) var settingsBeforePreset: AppSettings?

    /// Applique une disposition prête à l'emploi (modules avec carte, pages, tailles).
    func apply(_ preset: LayoutPreset) {
        settingsBeforePreset = settings.settings
        let known = Set(availableModules.map { $0.descriptor.id })
        for type in availableModules where type.descriptor.providesWidget {
            settings.settings.moduleEnabled[type.descriptor.id] = preset.enabledIDs.contains(type.descriptor.id)
        }
        settings.settings.widgetLayout = WidgetLayout(
            pages: preset.pages.map { $0.filter(known.contains) }.filter { !$0.isEmpty },
            sizes: preset.sizes
        )
        reload()
    }

    /// Revient aux réglages d'avant la dernière disposition appliquée.
    func undoPreset() {
        guard let previous = settingsBeforePreset else { return }
        settings.settings.moduleEnabled = previous.moduleEnabled
        settings.settings.widgetLayout = previous.widgetLayout
        settingsBeforePreset = nil
        reload()
    }

    /// Revient à la disposition automatique et aux tailles par défaut.
    func resetLayout() {
        settings.settings.widgetLayout = nil
    }

    // MARK: - Modification

    func setEnabled(_ enabled: Bool, for id: String) {
        settings.settings.moduleEnabled[id] = enabled
        if !enabled, let layout = settings.settings.widgetLayout {
            settings.settings.widgetLayout = WidgetLayoutEngine.remove(id, from: layout)
        }
        reload()
    }

    /// Active un module et le place à une position donnée (glisser depuis « Widgets masqués »).
    func enable(_ id: String, atPage page: Int, index: Int) {
        let layout = editableLayout
        settings.settings.moduleEnabled[id] = true
        reload()
        settings.settings.widgetLayout = WidgetLayoutEngine.move(id, toPage: page, index: index, in: layout)
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
                    let module = type.init(context: makeContext(for: descriptor.id))
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

    private func makeContext(for moduleID: String) -> ModuleContext {
        ModuleContext(
            presentAlert: { [weak self] alert in self?.alertHandler?(alert) },
            openSettings: { [weak self] in self?.settingsHandler?(moduleID) },
            holdExpanded: { [weak self] hold in self?.holdHandler?(hold) },
            dismissAlert: { [weak self] id in self?.dismissAlertHandler?(id) },
            blockExpansion: { [weak self] blocked in self?.blockExpansionHandler?(blocked) }
        )
    }
}
