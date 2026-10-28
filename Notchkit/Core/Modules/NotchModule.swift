import SwiftUI

/// Importance d'un module pour l'affichage compact (encoche repliée).
/// Le gestionnaire affiche le module ayant la priorité la plus haute ;
/// à priorité égale, c'est l'ordre choisi par l'utilisateur qui l'emporte.
enum ModulePriority: Int, Comparable, Sendable {
    /// Rien à afficher en mode compact.
    case none = 0
    /// Information de fond (ex. l'heure).
    case low = 10
    /// Activité en cours (ex. minuteur, téléchargement).
    case normal = 50
    /// Activité en cours plus importante (ex. Claude Code qui travaille).
    case elevated = 75
    /// Activité qui attend une réponse (Claude Code demande une autorisation) : devant toutes les
    /// activités en cours, sauf la musique en lecture, qui la laisse dans une bulle.
    case urgentActivity = 80
    /// Musique en lecture : passe devant toutes les activités en cours, comme sur l'iPhone ; seule une
    /// information urgente (`high`) la relègue dans une bulle.
    case media = 90
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

    /// Autre module actif, par identifiant (ex. le module Agents lit les sessions de Claude Code).
    var otherModule: @MainActor (String) -> (any NotchModule)? = { _ in nil }
    /// Déplie l'encoche sur la page de ce module (ex. un agent attend une réponse).
    var showModule: @MainActor () -> Void = {}
    /// Mascotte choisie dans les réglages.
    var mascot: @MainActor () -> MascotDesign = { .pip }
    /// Encoche discrète (mode jeu) : ni survol, ni alertes, ni bulles.
    var setQuietMode: @MainActor (Bool) -> Void = { _ in }

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
    /// Widget à ouvrir quand on déplie l'encoche pendant l'activité de ce module (lui-même par défaut ;
    /// ex. Claude Code ouvre la page Agents).
    var widgetModuleID: String { get }
    var compactPriority: ModulePriority { get }

    /// Contenu affiché à gauche de l'encoche quand elle est repliée.
    func compactLeading() -> AnyView?
    /// Contenu affiché à droite de l'encoche quand elle est repliée.
    func compactTrailing() -> AnyView?
    /// Couleur du contour de l'encoche (et de la bulle) pendant l'activité, comme la « key line »
    /// de la Dynamic Island (HIG, Live Activities) : orange pour un minuteur, teinte de la pochette
    /// pour la musique… `nil` : gris clair.
    var keyLineColor: Color? { get }
    /// Affichage replié façon « Dynamic Island » : capsule un peu plus haute, avec contour.
    var compactIsland: Bool { get }
    /// Largeur de chaque côté de l'encoche repliée : juste la place du contenu le plus long
    /// (fixe, pour que la forme ne saute pas quand un chiffre change).
    var compactSideWidth: CGFloat { get }
    /// Priorité en bulle (activité secondaire, à droite de l'encoche) ; `compactPriority` par défaut.
    /// Ex. la musique en pause garde sa bulle pour pouvoir la relancer, sans occuper l'encoche.
    var bubblePriority: ModulePriority { get }
    /// Commandes qui sortent à droite de sa bulle au survol, sans déplier l'encoche
    /// (ex. précédent, lecture/pause, suivant pour la musique). `nil` : le survol ouvre sa page.
    func bubbleControls() -> AnyView?
    /// Largeur gagnée par la bulle quand elle montre ses commandes.
    var bubbleControlsWidth: CGFloat { get }
    /// Le survol de sa bulle (sans commandes) ouvre sa page ; faux : seulement un clic (ex. Claude Code,
    /// dont la bulle reste longtemps à côté de la musique et s'ouvrait au moindre passage).
    var bubbleOpensOnHover: Bool { get }
    /// Écran verrouillé : version élargie et cliquable de l'activité (ex. lecteur de musique), à la
    /// place de `compactLeading/Trailing`. `nil` : l'activité reste affichée sans interaction.
    func lockScreenLeading() -> AnyView?
    func lockScreenTrailing() -> AnyView?
    /// Écran verrouillé : grand lecteur affiché au milieu de l'écran, sous l'heure de macOS (pochette et
    /// panneau en verre), à la place de `lockScreenLeading/Trailing`. `nil` : pas de grand lecteur.
    func lockScreenMedia() -> AnyView?
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
    var widgetModuleID: String { Self.descriptor.id }

    var hasContextualContent: Bool { false }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
    func bubbleControls() -> AnyView? { nil }
    var bubbleControlsWidth: CGFloat { NotchLayout.bubbleControlsContentWidth }
    var bubbleOpensOnHover: Bool { true }
    func lockScreenLeading() -> AnyView? { nil }
    func lockScreenTrailing() -> AnyView? { nil }
    func lockScreenMedia() -> AnyView? { nil }
    var bubblePriority: ModulePriority { compactPriority }
    var keyLineColor: Color? { nil }
    var compactIsland: Bool { false }
    var compactSideWidth: CGFloat { NotchLayout.activitySideWidth }
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
    /// Garde la légende, en petit, même dans une mini empilée (sinon masquée quand il y a une valeur).
    var keepsCaption = false

    init(value: String?, caption: String? = nil, tint: Color = .white, keepsCaption: Bool = false,
         @ViewBuilder visual: () -> Visual) {
        self.visual = visual()
        self.value = value
        self.caption = caption
        self.tint = tint
        self.keepsCaption = keepsCaption
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
                if let caption, !isShort || value == nil || keepsCaption {
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
