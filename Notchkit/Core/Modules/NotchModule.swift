import SwiftUI

/// Importance d'un module pour l'affichage compact (encoche repliée).
/// Le gestionnaire affiche le module ayant la priorité la plus haute ;
/// à priorité égale, c'est l'ordre choisi par l'utilisateur qui l'emporte.
enum ModulePriority: Int, Comparable, Sendable {
    /// Rien à afficher en mode compact.
    case none = 0
    /// Information de fond (ex. l'heure).
    case low = 10
    /// Activité en cours (ex. musique en lecture).
    case normal = 50
    /// Activité en cours plus importante (ex. Claude Code qui travaille).
    case elevated = 75
    /// Information urgente (ex. minuteur qui se termine).
    case high = 100

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Services mis à disposition des modules par l'application.
@MainActor
struct ModuleContext {
    /// Affiche une alerte temporaire dans l'encoche (ex. branchement du chargeur).
    let presentAlert: @MainActor (NotchAlert) -> Void
    /// Ouvre la fenêtre de réglages de l'app.
    let openSettings: @MainActor () -> Void
    /// Garde l'encoche dépliée (ex. pendant la saisie d'un message), même si la souris s'éloigne.
    let holdExpanded: @MainActor (Bool) -> Void
    /// Retire une alerte avant la fin de sa durée.
    var dismissAlert: @MainActor (UUID) -> Void = { _ in }

    func dismiss(_ alertID: UUID) { dismissAlert(alertID) }
}

/// Protocole commun à toutes les fonctionnalités de Notchkit.
///
/// Cycle de vie :
/// 1. le `ModuleManager` crée le module avec `init(context:)` quand il est activé ;
/// 2. il appelle `start()` : le module s'abonne à ses sources de données ;
/// 3. à la désactivation, il appelle `stop()` : le module doit tout libérer
///    (observateurs, timers…) pour ne plus consommer ni CPU ni batterie.
///
/// Les modules sont des classes `@Observable` : les vues se mettent à jour
/// automatiquement quand leurs propriétés changent.
@MainActor
protocol NotchModule: AnyObject, Observable {
    static var descriptor: ModuleDescriptor { get }

    init(context: ModuleContext)

    func start()
    func stop()

    /// Priorité actuelle en mode compact. `.none` = le module ne demande pas d'affichage.
    var compactPriority: ModulePriority { get }

    /// Contenu affiché à gauche de l'encoche quand elle est repliée.
    func compactLeading() -> AnyView?
    /// Contenu affiché à droite de l'encoche quand elle est repliée.
    func compactTrailing() -> AnyView?
    /// Contenu affiché quand l'encoche est dépliée.
    func expandedView() -> AnyView
    /// Largeur relative de la carte dans l'encoche dépliée (1 = normale, 2 = double).
    var expandedWidthWeight: CGFloat { get }
    /// Version miniature (taille « Mini ») : l'information essentielle en un coup d'œil.
    func miniView() -> AnyView
    /// Réglages propres au module (affichés dans l'onglet « Modules »).
    func settingsView() -> AnyView?
}

// Implémentations par défaut : un module n'implémente que ce dont il a besoin.
extension NotchModule {
    var moduleID: String { Self.descriptor.id }

    func start() {}
    func stop() {}
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
    func settingsView() -> AnyView? { nil }
    var expandedWidthWeight: CGFloat { 1 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: Self.descriptor.systemImage, value: nil, caption: String(localized: Self.descriptor.name)))
    }
}

/// Mise en page commune des widgets « Mini » : un visuel, une valeur, une légende.
struct MiniWidget<Visual: View>: View {
    let visual: Visual
    let value: String?
    let caption: String?
    var tint: Color = .white

    init(value: String?, caption: String? = nil, tint: Color = .white, @ViewBuilder visual: () -> Visual) {
        self.visual = visual()
        self.value = value
        self.caption = caption
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 6) {
            visual
                .frame(height: 34)
            if let value {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension MiniWidget where Visual == AnyView {
    init(symbol: String, value: String?, caption: String? = nil, tint: Color = .white) {
        self.init(value: value, caption: caption, tint: tint) {
            AnyView(Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint))
        }
    }
}
