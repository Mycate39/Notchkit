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

    /// Empêche temporairement l'encoche de s'ouvrir au survol (ex. bouton cliquable en mode replié).
    var blockExpansion: @MainActor (Bool) -> Void = { _ in }

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

    /// Module contextuel (`descriptor.contextual`) au widget masqué : vrai s'il a du contenu à montrer
    /// (ex. fichiers posés sur l'étagère). Il s'affiche alors en dernière page de l'encoche.
    var hasContextualContent: Bool { get }

    init(context: ModuleContext)

    func start()
    func stop()

    /// Priorité actuelle en mode compact. `.none` = le module ne demande pas d'affichage.
    var compactPriority: ModulePriority { get }

    /// Contenu affiché à gauche de l'encoche quand elle est repliée.
    func compactLeading() -> AnyView?
    /// Contenu affiché à droite de l'encoche quand elle est repliée.
    func compactTrailing() -> AnyView?
    /// Affichage replié façon « Dynamic Island » : capsule un peu plus haute, avec contour.
    var compactIsland: Bool { get }
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

    var hasContextualContent: Bool { false }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
    var compactIsland: Bool { false }
    func settingsView() -> AnyView? { nil }
    var expandedWidthWeight: CGFloat { 1 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(value: nil, caption: String(localized: Self.descriptor.name)) {
            ModuleIcon(symbol: Self.descriptor.systemImage)
        })
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
        // Le contenu s'adapte à la taille réelle du widget (Mini pleine hauteur ou empilé).
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let isShort = height < 100
            let visualSide = isShort ? min(width * 0.5, height * 0.4) : min(width * 0.62, height * 0.34)
            let valueSize = isShort ? min(width * 0.24, height * 0.24) : min(width * 0.28, height * 0.15)
            let captionSize = max(8, min(width * 0.14, height * 0.085))

            VStack(spacing: height * (isShort ? 0.03 : 0.05)) {
                // Visuel dessiné à une taille de référence puis agrandi pour remplir l'espace.
                visual
                    .frame(width: Self.baseSide * 1.6, height: Self.baseSide)
                    .scaleEffect(visualSide / Self.baseSide)
                    .frame(width: width, height: visualSide)
                if let value {
                    Text(value)
                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        // Valeur toujours sur une ligne (« ≈ 49 % » ne doit pas se couper en deux).
                        .lineLimit(1)
                }
                if let caption, !isShort || value == nil {
                    Text(caption)
                        .font(.system(size: captionSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
            }
            .lineLimit(isShort ? 1 : 2)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, width * 0.06)
            .frame(width: width, height: height)
        }
    }

    /// Taille de référence des visuels (agrandis ensuite selon la place disponible).
    private static var baseSide: CGFloat { 34 }
}

extension MiniWidget where Visual == AnyView {
    init(symbol: String, value: String?, caption: String? = nil, tint: Color = .white) {
        self.init(value: value, caption: caption, tint: tint) {
            AnyView(Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint))
        }
    }
}
