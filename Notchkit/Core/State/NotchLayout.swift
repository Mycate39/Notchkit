import AppKit
import SwiftUI

/// Apparence de base de la zone interactive.
enum NotchStyle: Sendable {
    /// Collée au bord supérieur, prolonge l'encoche physique (ou simulée).
    case notch
    /// Pastille flottante en haut de l'écran (Mac sans encoche).
    case pill
}

/// Description géométrique de l'écran cible, calculée par `ScreenLocator`.
struct NotchGeometry: Equatable, Sendable {
    var style: NotchStyle
    /// Taille de la zone au repos : l'encoche physique, ou la pastille.
    var closedSize: CGSize
    /// Cadre de l'écran cible (coordonnées AppKit, origine en bas à gauche).
    var screenFrame: CGRect
    /// Centre horizontal de l'encoche, en coordonnées écran.
    var centerX: CGFloat
    /// Encoche matérielle (et non simulée ou pastille) : au repos, on ne dessine rien par-dessus.
    var isPhysicalNotch = false

    static let placeholder = NotchGeometry(
        style: .pill,
        closedSize: CGSize(width: 96, height: 20),
        screenFrame: .zero,
        centerX: 0
    )
}

/// Toutes les dimensions et animations de l'encoche, réunies au même endroit.
/// Fonctions pures : faciles à tester et à ajuster.
enum NotchLayout {
    /// Rayon des petits « congés » concaves qui raccordent l'encoche au bord de l'écran.
    static let earRadius: CGFloat = 8
    /// Largeur ajoutée de chaque côté de l'encoche pour le contenu compact.
    static let compactSideWidth: CGFloat = 72
    /// Taille de l'encoche dépliée.
    /// Apparence en vigueur (mise à jour par l'AppDelegate quand les réglages changent ;
    /// lue et écrite uniquement sur le thread principal).
    nonisolated(unsafe) static var appearance = NotchAppearance()

    static var expandedSize: CGSize { appearance.expandedSize }
    /// Décalage de la pastille par rapport au haut de l'écran.
    static let pillTopInset: CGFloat = 3
    /// Hauteur ajoutée à la pastille en affichage « île » (lecture de musique).
    static let islandExtraHeight: CGFloat = 6
    /// Proportions de l'île (largeur / hauteur), comme la Dynamic Island pendant la lecture.
    static let islandAspectRatio: CGFloat = 4.8
    /// Ombre portée par la forme : petite au survol, plus large une fois dépliée.
    struct Shadow: Equatable {
        var opacity: Double
        var radius: CGFloat
        var y: CGFloat

        /// Place nécessaire sous la forme pour que le flou s'estompe avant le bord de la fenêtre
        /// (sinon l'ombre est tranchée net et dessine une ligne) : décalage plus deux rayons de flou.
        var margin: CGFloat { (y + radius * 2).rounded(.up) }
    }
    static let hoverShadow = Shadow(opacity: 0.45, radius: 5, y: 2)
    static let expandedShadow = Shadow(opacity: 0.5, radius: 16, y: 6)
    /// Marge de fenêtre réservée à l'ombre de survol (sur les côtés et en bas).
    static var hoverShadowMargin: CGFloat { hoverShadow.margin }
    /// Marge de fenêtre réservée à l'ombre de l'encoche dépliée.
    static var expandedShadowMargin: CGFloat { expandedShadow.margin }
    /// Activités secondaires : une seule bulle à droite de l'encoche. À partir de deux, elles sont
    /// rangées dans une pile qui se déroule au survol (au plus `maxBubbles` bulles).
    static let maxBubbles = 4
    static let bubbleGap: CGFloat = 6
    /// Décalage du menu déroulé sous le bord de l'écran, en mode encoche.
    static let bubbleMenuTopInset: CGFloat = 4

    /// Forme noire dessinée ? (fonction pure, testée). Sur une encoche matérielle au repos, une
    /// forme par-dessus serait un peu plus large (congés) et ses coins ne tomberaient pas
    /// exactement sur ceux de l'écran : bords crénelés. On laisse alors l'encoche réelle seule.
    static func showsShape(isPhysicalNotch: Bool, isExpanded: Bool, hasCompactContent: Bool,
                           isHovering: Bool, hasBubbles: Bool) -> Bool {
        !isPhysicalNotch || isExpanded || hasCompactContent || isHovering || hasBubbles
    }

    /// Juste après un repli, l'encoche ne se rouvre que si le pointeur s'y attarde : en remontant
    /// vers la barre des menus, on la traverse sans le vouloir.
    static let reopenGuardWindow: TimeInterval = 1.0
    static let reopenGuardDelay: TimeInterval = 0.5

    /// Délai d'ouverture au survol (fonction pure, testée) : allongé pendant `reopenGuardWindow`
    /// après un repli, sinon le délai choisi dans les réglages.
    static func openDelay(base: TimeInterval, sinceCollapse: TimeInterval?) -> TimeInterval {
        guard let sinceCollapse, sinceCollapse < reopenGuardWindow else { return base }
        return max(base, reopenGuardDelay)
    }

    /// Hauteur d'une encoche physique. La zone de sécurité (32 pt sur un MacBook Pro 14") s'arrête
    /// environ 1 pt au-dessus du bas réel de l'encoche, qui coïncide avec la barre des menus (33 pt).
    /// On prend la plus grande des deux ; si la barre est masquée (hauteur 0), la zone de sécurité.
    static func physicalNotchHeight(safeAreaTop: CGFloat, menuBarHeight: CGFloat) -> CGFloat {
        max(safeAreaTop, menuBarHeight)
    }

    /// Diamètre d'une bulle : la hauteur de l'encoche repliée (île comprise, pour rester alignée).
    static func bubbleDiameter(for geometry: NotchGeometry, island: Bool = false) -> CGFloat {
        geometry.closedSize.height + (island && geometry.style == .pill ? islandExtraHeight : 0)
    }

    /// Largeur d'une bulle. En mode encoche, c'est une mini-encoche suspendue au bord de l'écran :
    /// un peu plus large que haute, avec les mêmes congés arrondis que la grande.
    static func bubbleWidth(for geometry: NotchGeometry, island: Bool = false) -> CGFloat {
        let diameter = bubbleDiameter(for: geometry, island: island)
        guard geometry.style == .notch else { return diameter }
        return (diameter * 1.25).rounded() + earRadius * 2
    }

    /// Largeur réservée à droite de l'encoche : une seule place (bulle ou pile), espacement compris.
    static func bubblesWidth(count: Int, geometry: NotchGeometry, island: Bool = false) -> CGFloat {
        count > 0 ? bubbleWidth(for: geometry, island: island) + bubbleGap : 0
    }

    /// Souris au-dessus de la grande encoche plutôt que des bulles (même fenêtre) ?
    /// - Parameters:
    ///   - dx: écart horizontal au centre de la fenêtre ;
    ///   - fromTop: distance au bord haut de l'écran.
    static func isOverNotch(dx: CGFloat, fromTop: CGFloat, shapeSize: CGSize, style: NotchStyle) -> Bool {
        let tolerance: CGFloat = 4
        return abs(dx) <= shapeSize.width / 2 + tolerance
            && fromTop <= topInset(for: style) + shapeSize.height + tolerance
    }

    /// Pointeur dans l'encoche ? (fonction pure, testée). Dépliée : toute la fenêtre lui appartient.
    /// Sinon, seulement la forme repliée : pendant le repli, la fenêtre a encore la taille de
    /// l'encoche dépliée, et un pointeur resté (ou passant) dans cette grande zone la rouvrait.
    static func isPointerInside(isExpanded: Bool, dx: CGFloat, fromTop: CGFloat, shapeSize: CGSize,
                                style: NotchStyle) -> Bool {
        isExpanded || isOverNotch(dx: dx, fromTop: fromTop, shapeSize: shapeSize, style: style)
    }

    /// Hauteur du menu déroulé : `count` bulles rondes empilées (décalage du haut compris).
    static func bubbleMenuHeight(count: Int, geometry: NotchGeometry, island: Bool = false) -> CGFloat {
        let count = min(max(0, count), maxBubbles)
        guard count > 0 else { return 0 }
        let diameter = bubbleDiameter(for: geometry, island: island)
        let top = geometry.style == .notch ? bubbleMenuTopInset : 0
        return top + CGFloat(count) * diameter + CGFloat(count - 1) * bubbleGap
    }

    /// Rayon des coins en mode déplié.
    static let expandedCornerRadius: CGFloat = 24

    /// Facteur de ralentissement des animations (menu Débogage, pour observer un défaut).
    @MainActor static var animationSlowdown: Double = 1

    /// Animation principale (ressort court et peu rebondissant, pour rester fluide).
    @MainActor static var spring: Animation {
        // « Réduire les animations » (Accessibilité de macOS) est toujours respecté.
        // « Réduire les animations » : courte transition douce, sans ressort ni dépassement.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .easeOut(duration: 0.18 * animationSlowdown) }
        let style = appearance.animation
        return .spring(duration: style.spring.duration * animationSlowdown, bounce: style.spring.bounce)
    }
    /// Disparition de la forme au-dessus d'une vraie encoche : seulement une fois le repli terminé,
    /// sinon le fondu se joue pendant le repli et le rend presque invisible.
    @MainActor static var shapeFadeOut: Animation {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let collapse = reduceMotion ? 0.18 : appearance.animation.spring.duration
        return .easeOut(duration: 0.2 * animationSlowdown).delay(collapse * animationSlowdown)
    }
    /// Part du repli après laquelle l'activité compacte ressort : le ressort a presque fini sa course
    /// bien avant sa durée nominale, attendre la fin laisse un temps mort.
    static let collapseSettleFraction = 0.6
    /// Attente avant que l'activité compacte ressorte au repli.
    @MainActor static var collapseSettleDelay: Duration {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let collapse = reduceMotion ? 0.18 : appearance.animation.spring.duration
        return .milliseconds(Int(collapse * collapseSettleFraction * 1000 * animationSlowdown))
    }
    /// Durée pendant laquelle l'indicateur de pages reste visible après un balayage.
    static let pageIndicatorLinger: Duration = .milliseconds(1200)
    /// Ressort de l'indicateur de pages : la pastille glisse d'une page à l'autre avec un léger rebond.
    static let pageIndicatorSpring = Animation.spring(duration: 0.4, bounce: 0.3)

    // MARK: Centre du son

    /// Onglets et lignes d'appareils : assez hauts pour être visés sans précision.
    static let audioTabHeight: CGFloat = 24
    static let audioRowHeight: CGFloat = 26

    // MARK: Curseurs

    /// Hauteur minimale de la zone cliquable d'un curseur, quelle que soit l'épaisseur de la barre.
    static let sliderMinimumHitHeight: CGFloat = 24

    static func sliderHitHeight(for barHeight: CGFloat) -> CGFloat {
        max(barHeight, sliderMinimumHitHeight)
    }

    /// Loupe de verre : un peu plus haute que la barre, et plus grosse pendant le glissement.
    static func sliderKnobSize(for barHeight: CGFloat, isDragging: Bool) -> CGSize {
        let height = isDragging ? min(barHeight + 10, barHeight * 1.6) : barHeight + 4
        return CGSize(width: height * 1.6, height: height)
    }

    /// Position de la loupe : centrée sur le bout du remplissage, sans sortir du rail.
    static func sliderKnobOffset(fraction: Double, trackWidth: CGFloat, knobWidth: CGFloat) -> CGFloat {
        let centered = trackWidth * CGFloat(min(max(fraction, 0), 1)) - knobWidth / 2
        return min(max(centered, 0), max(0, trackWidth - knobWidth))
    }
    /// Temps laissé à l'animation de repli avant de réduire la fenêtre.
    @MainActor static var shrinkDelay: Duration {
        .milliseconds(500) * animationSlowdown
    }

    /// Taille de la forme noire selon l'état.
    static func shapeSize(for geometry: NotchGeometry, isExpanded: Bool, hasCompactContent: Bool,
                          sideWidth: CGFloat = compactSideWidth, alertSize: CGSize? = nil,
                          island: Bool = false) -> CGSize {
        let ears = geometry.style == .notch ? earRadius * 2 : 0
        let closed = geometry.closedSize

        // Alerte agrandie (ex. animation de déverrouillage).
        if !isExpanded, let alertSize {
            return CGSize(width: max(alertSize.width, closed.width) + ears, height: max(alertSize.height, closed.height))
        }

        if isExpanded {
            let width = max(expandedSize.width, closed.width + compactSideWidth * 2)
            return CGSize(width: width + ears, height: max(expandedSize.height, closed.height))
        }

        guard hasCompactContent else {
            return CGSize(width: closed.width + ears, height: closed.height)
        }

        if island && geometry.style == .pill {
            // Île : un peu plus haute que la pastille, aux proportions de la Dynamic Island.
            let height = closed.height + islandExtraHeight
            return CGSize(width: max(closed.width, (height * islandAspectRatio).rounded()), height: height)
        }

        switch geometry.style {
        case .notch:
            // Le contenu se place de part et d'autre de l'encoche physique.
            return CGSize(width: closed.width + sideWidth * 2 + ears, height: closed.height)
        case .pill:
            // Pas d'encoche physique à contourner : la pastille s'élargit simplement.
            return CGSize(width: max(closed.width, sideWidth * 2 + 8), height: closed.height)
        }
    }

    /// Largeur totale (en poids de cartes) d'une page de l'encoche dépliée.
    static var pageCapacity: CGFloat { appearance.pageCapacity }

    /// Répartit les cartes en pages, dans l'ordre, sans dépasser `capacity` par page.
    /// Renvoie les indices des cartes de chaque page. Une carte trop large occupe une page seule.
    static func paginate(weights: [CGFloat], capacity: CGFloat = pageCapacity) -> [[Int]] {
        var pages: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, weight) in weights.enumerated() {
            if !current.isEmpty && used + weight > capacity {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(index)
            used += weight
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    /// Espace entre le haut de l'écran et la forme.
    static func topInset(for style: NotchStyle) -> CGFloat {
        style == .pill ? pillTopInset : 0
    }

    /// Taille de la fenêtre nécessaire pour contenir la forme.
    static func panelSize(for geometry: NotchGeometry, isExpanded: Bool, hasCompactContent: Bool,
                          sideWidth: CGFloat = compactSideWidth, alertSize: CGSize? = nil,
                          island: Bool = false) -> CGSize {
        let shape = shapeSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent,
                              sideWidth: sideWidth, alertSize: alertSize, island: island)
        return CGSize(width: shape.width, height: shape.height + topInset(for: geometry.style))
    }

    /// Rayons des coins (haut, bas) de la forme.
    static func cornerRadii(for style: NotchStyle, isExpanded: Bool, height: CGFloat,
                            island: Bool = false) -> (top: CGFloat, bottom: CGFloat) {
        switch style {
        case .notch:
            if island && !isExpanded { return (0, height / 2) }
            return (0, isExpanded ? expandedCornerRadius : min(10, height / 3))
        case .pill:
            let radius = isExpanded ? expandedCornerRadius : height / 2
            return (radius, radius)
        }
    }
}
