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
    /// Largeur ajoutée de chaque côté de l'encoche repliée : la même pour toutes les activités et
    /// alertes (musique, minuteur, chargeur, volume…), celle de la pochette et des barres de la musique.
    static let activitySideWidth: CGFloat = 38
    static let compactSideWidth: CGFloat = activitySideWidth
    /// Exception : l'indicateur de volume et de luminosité, dont la barre serait illisible à la largeur de la musique.
    static let levelIndicatorSideWidth: CGFloat = 80
    /// Autre exception : une alerte qui écrit un mot à droite (« Connectés », « Terminé », « Copié »…),
    /// qui serait sinon coupé (« Co… ») à la largeur de la musique.
    static let textAlertSideWidth: CGFloat = 90
    /// Alerte à phrase courte (rappels de Santé : « Faites une pause »), sinon réduite et peu lisible.
    static let phraseAlertSideWidth: CGFloat = 120
    /// Lecteur de l'écran verrouillé (pochette et titre, commandes) : l'encoche s'élargit sans descendre.
    static let lockScreenSideWidth: CGFloat = 150
    /// Grand lecteur de l'écran verrouillé, sous l'heure de macOS : pochette carrée puis panneau en verre.
    struct LockScreenMedia: Equatable {
        /// Cadre de la fenêtre (coordonnées de l'écran, origine en bas à gauche), marges d'ombre comprises.
        var frame: CGRect
        var artwork: CGFloat
        var panel: CGSize
        /// Panneau quand la pochette y est rentrée (petite pochette à côté du titre, façon iOS).
        var compactPanelHeight: CGFloat = 0
        /// Petite pochette rentrée dans le panneau.
        var smallArtwork: CGFloat = 0
        var gap: CGFloat
        var margin: CGFloat
    }

    /// Arrondi du panneau en verre du grand lecteur.
    static let lockScreenPanelRadius: CGFloat = 26

    /// Délai minimal entre deux clics sur la pochette du grand lecteur (le second clic d'un double clic
    /// est ignoré).
    static let lockScreenArtworkToggleInterval: TimeInterval = 0.4

    /// Arrondi de la pochette du grand lecteur selon sa taille (24 pt en grand, 8 pt au moins en petit).
    static func lockScreenArtworkRadius(side: CGFloat) -> CGFloat { max(8, side * 0.057) }

    /// Place du grand lecteur sur un écran : pochette de 36 % de la hauteur (420 pt au plus) dont le haut
    /// est à 29 % de la hauteur, sous l'heure, puis le panneau.
    static func lockScreenMedia(screen: CGRect) -> LockScreenMedia {
        let artwork = min(420, (screen.height * 0.36).rounded())
        let panel = CGSize(width: 340, height: 150)
        let gap: CGFloat = 26
        let margin: CGFloat = 40
        let width = max(artwork, panel.width) + margin * 2
        let height = artwork + gap + panel.height + margin * 2
        let top = screen.maxY - (screen.height * 0.29).rounded() + margin
        let frame = CGRect(x: (screen.midX - width / 2).rounded(), y: top - height, width: width, height: height)
        return LockScreenMedia(frame: frame, artwork: artwork, panel: panel, compactPanelHeight: 168,
                               smallArtwork: 52, gap: gap, margin: margin)
    }

    /// Hauteur du fondu au bas des listes défilantes des widgets (rappels, presse-papiers, téléchargements).
    static let scrollFadeLength: CGFloat = 14
    /// Apparence en vigueur (mise à jour par l'AppDelegate quand les réglages changent ;
    /// lue et écrite uniquement sur le thread principal).
    nonisolated(unsafe) static var appearance = NotchAppearance()

    /// Encoche ouverte : pas de taille à choisir, elle suit les widgets de la page affichée. Hauteur
    /// selon le plus grand widget de la page (`expandedHeight(sizes:)`) : basse avec des Mini seulement,
    /// normale avec des Petit ou des Moyen, haute dès qu'il y a un Grand. Largeur selon les colonnes.
    static let expandedHeight: CGFloat = 190
    static let miniExpandedHeight: CGFloat = 150
    static let largeExpandedHeight: CGFloat = 222

    /// Hauteur de l'encoche ouverte d'après la taille des widgets de la page.
    static func expandedHeight(sizes: [WidgetSize]) -> CGFloat {
        if sizes.contains(.large) { return largeExpandedHeight }
        if !sizes.isEmpty, sizes.allSatisfy({ $0 == .mini }) { return miniExpandedHeight }
        return expandedHeight
    }
    /// Largeur d'un widget Petit (une unité) ; Mini, Moyen et Grand en font 0,5, 1,5 et 2.
    static let widgetUnitWidth: CGFloat = 140
    /// Marge entre les widgets et le bord de l'encoche, en plus du congé.
    static let pageSideMargin: CGFloat = 18
    /// Place gardée de chaque côté de l'encoche matérielle, dans l'en-tête de l'encoche ouverte : congé
    /// et marge du verre, engrenage des réglages (22 pt) et un peu d'air.
    static let expandedHeaderSideRoom: CGFloat = glassEarRadius + pageSideMargin + 28
    /// Fond « Verre » : ombre fine des textes et halo sous le contenu des widgets (`GlassLegibility`).
    static let glassContentShadowOpacity: Double = 0.9
    /// Encoche ouverte la plus étroite (onglets des pages et réglages dans l'en-tête) ; elle reste de
    /// toute façon au moins aussi large que l'encoche repliée avec ses activités (`shapeSize`).
    static let minExpandedWidth: CGFloat = 280

    /// Largeur et hauteur de l'encoche ouverte pour une page dont les colonnes ont ces poids (Petit = 1),
    /// sans les congés de base que la forme ajoute de chaque côté (`shapeSize`).
    static func expandedSize(columnWeights: [CGFloat], glass: Bool, height: CGFloat = expandedHeight) -> CGSize {
        let gap = widgetSpacing(onGlass: glass).columns
        let content = columnWeights.reduce(0, +) * widgetUnitWidth + gap * CGFloat(max(0, columnWeights.count - 1))
        let margins = 2 * (earRadius(glass: glass, isExpanded: true) + pageSideMargin) - 2 * earRadius
        return CGSize(width: max(minExpandedWidth, (content + margins).rounded()), height: height)
    }

    /// Page pleine (quatre widgets Petit) : page vide, zones de dépôt, éditeur de disposition.
    static var defaultExpandedSize: CGSize { expandedSize(columnWeights: [1, 1, 1, 1], glass: false) }

    /// Plus grande encoche ouverte possible (taille de la vue dans la fenêtre) : une page pleine de
    /// colonnes de Mini, avec les écarts du verre, ou le lecteur de musique.
    static var maxExpandedSize: CGSize {
        let widest = expandedSize(columnWeights: Array(repeating: 0.5, count: Int(pageCapacity * 2)), glass: true)
        return CGSize(width: widest.width, height: largeExpandedHeight)
    }
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
    /// Fond « Verre » de l'encoche ouverte, façon lecteur de l'iPhone : noir plein sur le haut (au moins
    /// l'encoche matérielle), long dégradé, puis verre clair où le fond d'écran reste visible, à peine
    /// assombri en bas ; pas de contour, seul le bord du verre.
    static let glassBlackFraction: CGFloat = 0.38
    static let glassBottomDarkness: Double = 0.08
    static let glassTint: Double = 0.05
    /// Écart entre deux widgets : sans carte (fond « Verre »), seul le vide les sépare.
    static func widgetSpacing(onGlass: Bool) -> (columns: CGFloat, stacked: CGFloat) {
        onGlass ? (22, 14) : (10, 8)
    }
    static let expandedShadow = Shadow(opacity: 0.5, radius: 16, y: 6)
    /// Marge de fenêtre réservée à l'ombre de survol (sur les côtés et en bas).
    static var hoverShadowMargin: CGFloat { hoverShadow.margin }
    /// Marge de fenêtre réservée à l'ombre de l'encoche dépliée.
    static var expandedShadowMargin: CGFloat { expandedShadow.margin }
    /// Activités secondaires : une seule bulle à droite de l'encoche. À partir de deux, elles sont
    /// rangées dans une pile qui se déroule au survol (au plus `maxBubbles` bulles).
    static let maxBubbles = 4
    static let bubbleGap: CGFloat = 6
    /// Points de la pile (un par activité), en colonne le long du bord gauche de la bulle.
    static let bubbleDotSize: CGFloat = 3
    static let bubbleDotSpacing: CGFloat = 2.5
    /// Commandes d'une bulle (musique) : elles sortent peu après l'arrivée de la souris
    /// et rentrent un peu après son départ (passer de la bulle aux commandes ne les referme pas).
    static let bubbleControlsOpenDelay: TimeInterval = 0.12
    static let bubbleControlsCloseDelay: TimeInterval = 0.3
    /// Contour de l'encoche et des bulles : teinte de l'activité, ou gris clair par défaut.
    static func keyLine(_ tint: Color?) -> Color {
        tint?.opacity(0.55) ?? .white.opacity(0.22)
    }

    /// Largeur gagnée par la bulle qui montre ses commandes : trois boutons (musique) par défaut,
    /// deux pour un minuteur, plus son temps restant.
    static let bubbleControlsContentWidth: CGFloat = 100
    static let timerBubbleControlsWidth: CGFloat = 72

    /// Bulle allongée d'un minuteur : deux boutons et le temps restant (« 4:32 », ou « 1:04:32 » à
    /// partir d'une heure, plus large).
    static func timerBubbleControlsWidth(showsHours: Bool) -> CGFloat {
        timerBubbleControlsWidth + (showsHours ? 64 : 46)
    }

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

    /// Hauteur du menu déroulé : la première bulle suspendue au bord, les autres rondes en dessous.
    static func bubbleMenuHeight(count: Int, geometry: NotchGeometry, island: Bool = false) -> CGFloat {
        let count = min(max(0, count), maxBubbles)
        guard count > 0 else { return 0 }
        let diameter = bubbleDiameter(for: geometry, island: island)
        return CGFloat(count) * diameter + CGFloat(count - 1) * bubbleGap
    }

    /// Rayon des coins en mode déplié.
    static let expandedCornerRadius: CGFloat = 24
    /// Fond « Verre », encoche ouverte : grands congés en haut et grands coins en bas, comme le lecteur
    /// de l'iPhone.
    static let glassEarRadius: CGFloat = 20
    static let glassCornerRadius: CGFloat = 36
    /// Fond « Verre » : une page qui ne contient que la musique ouvre l'encoche à la taille du lecteur
    /// de l'iPhone (deux fois plus large que haute) ; elle s'agrandit en passant à une autre page.
    static let glassMusicPlayerSize = CGSize(width: 440, height: largeExpandedHeight)

    /// Page qui ne contient que la musique, en mode verre : présentée en lecteur (`glassMusicPlayerSize`).
    static func isMusicPlayerPage(moduleIDs: [String], glass: Bool) -> Bool {
        glass && moduleIDs == ["music"]
    }

    /// Taille de l'encoche ouverte pour une page : lecteur pour la musique seule en mode verre, page
    /// pleine pour un widget pleine page (Agents), sinon d'après la largeur de ses colonnes de widgets.
    static func pageSize(moduleIDs: [String], sizes: [WidgetSize], fullPage: Bool, glass: Bool) -> CGSize {
        if isMusicPlayerPage(moduleIDs: moduleIDs, glass: glass) { return glassMusicPlayerSize }
        let height = expandedHeight(sizes: sizes)
        if fullPage {
            return expandedSize(columnWeights: Array(repeating: 1, count: Int(pageCapacity)), glass: glass, height: height)
        }
        let weights = WidgetColumns.make(sizes: sizes).map { sizes[$0[0]].weight }
        return expandedSize(columnWeights: weights, glass: glass, height: height)
    }

    /// Congé qui raccorde l'encoche au haut de l'écran.
    static func earRadius(glass: Bool, isExpanded: Bool) -> CGFloat {
        glass && isExpanded ? glassEarRadius : earRadius
    }

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

    /// Épaisseur du rail (fin, comme sur iOS).
    static func sliderTrackThickness(for height: CGFloat) -> CGFloat {
        max(4, (height * 0.22).rounded())
    }

    /// Pastille : capsule blanche au repos, plus grosse pendant le glissement.
    static func sliderKnobSize(for height: CGFloat, isDragging: Bool) -> CGSize {
        let base = max(12, height * 0.82)
        let knobHeight = isDragging ? base * 1.3 : base
        return CGSize(width: knobHeight * 1.7, height: knobHeight)
    }

    /// Centre de la pastille : elle reste entière dans le rail, de bout en bout.
    static func sliderKnobCenter(fraction: Double, trackWidth: CGFloat, knobWidth: CGFloat) -> CGFloat {
        let travel = max(0, trackWidth - knobWidth)
        return knobWidth / 2 + travel * CGFloat(min(max(fraction, 0), 1))
    }

    /// Valeur (0…1) à la position `x` (inverse de `sliderKnobCenter`).
    static func sliderFraction(atX x: CGFloat, trackWidth: CGFloat, knobWidth: CGFloat) -> Double {
        let travel = trackWidth - knobWidth
        guard travel > 0 else { return x >= trackWidth / 2 ? 1 : 0 }
        return Double(min(max((x - knobWidth / 2) / travel, 0), 1))
    }
    /// Gel de l'affichage de l'encoche pendant un changement de bureau au trackpad, mesuré sur les prises
    /// du diagnostic : une alerte affichée est prolongée d'autant.
    static let spaceTransition: Duration = .milliseconds(1100)

    /// Temps laissé à l'animation de repli avant de réduire la fenêtre.
    @MainActor static var shrinkDelay: Duration {
        .milliseconds(500) * animationSlowdown
    }

    /// Taille de la forme noire selon l'état.
    static func shapeSize(for geometry: NotchGeometry, isExpanded: Bool, hasCompactContent: Bool,
                          sideWidth: CGFloat = compactSideWidth, alertSize: CGSize? = nil,
                          island: Bool = false, pageSize: CGSize? = nil) -> CGSize {
        let ears = geometry.style == .notch ? earRadius * 2 : 0
        let closed = geometry.closedSize

        // Alerte agrandie (ex. animation de déverrouillage).
        if !isExpanded, let alertSize {
            return CGSize(width: max(alertSize.width, closed.width) + ears, height: max(alertSize.height, closed.height))
        }

        if isExpanded {
            let target = pageSize ?? defaultExpandedSize
            // Vraie encoche : l'en-tête est à sa hauteur ; il faut de la place de chaque côté de l'encoche
            // matérielle pour les onglets et l'engrenage, sinon ils passent sous la caméra.
            let side = geometry.style == .notch ? max(compactSideWidth, expandedHeaderSideRoom - earRadius) : compactSideWidth
            let width = max(target.width, closed.width + side * 2)
            return CGSize(width: width + ears, height: max(target.height, closed.height))
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
    static let pageCapacity: CGFloat = 4

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
                          island: Bool = false, pageSize: CGSize? = nil) -> CGSize {
        let shape = shapeSize(for: geometry, isExpanded: isExpanded, hasCompactContent: hasCompactContent,
                              sideWidth: sideWidth, alertSize: alertSize, island: island, pageSize: pageSize)
        return CGSize(width: shape.width, height: shape.height + topInset(for: geometry.style))
    }

    /// Rayons des coins (haut, bas) de la forme.
    static func cornerRadii(for style: NotchStyle, isExpanded: Bool, height: CGFloat,
                            island: Bool = false, glass: Bool = false) -> (top: CGFloat, bottom: CGFloat) {
        switch style {
        case .notch:
            if island && !isExpanded { return (0, height / 2) }
            if isExpanded { return (0, glass ? glassCornerRadius : expandedCornerRadius) }
            return (0, min(10, height / 3))
        case .pill:
            let radius = isExpanded ? expandedCornerRadius : height / 2
            return (radius, radius)
        }
    }
}
