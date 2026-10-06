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
    /// Marge de fenêtre réservée à l'ombre de survol (sur les côtés et en bas).
    static let hoverShadowMargin: CGFloat = 12
    /// Marge de fenêtre réservée à l'ombre de l'encoche dépliée.
    static let expandedShadowMargin: CGFloat = 22
    /// Bulles des activités secondaires (comme sur iPhone) : nombre maximal et espacement.
    static let maxBubbles = 2
    static let bubbleGap: CGFloat = 6

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

    /// Largeur occupée par `count` bulles à droite de l'encoche (espacements compris).
    static func bubblesWidth(count: Int, geometry: NotchGeometry, island: Bool = false) -> CGFloat {
        let count = min(max(0, count), maxBubbles)
        return CGFloat(count) * (bubbleWidth(for: geometry, island: island) + bubbleGap)
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
