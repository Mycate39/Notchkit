import CoreGraphics

/// Balayage des pages de l'encoche dépliée au trackpad, géré à la main (logique pure, testée).
///
/// Le défilement par pages de SwiftUI (`ScrollView` + `.paging`) restait parfois bloqué entre deux
/// pages dans le panneau de l'encoche. Ici, les pages suivent les doigts pendant le geste, puis
/// se calent au relâchement : page suivante, précédente, ou retour sur place. L'inertie du
/// trackpad est ignorée, une page par geste.
struct PageSwipe: Equatable {
    enum Axis: Equatable { case undecided, horizontal, vertical }

    /// Distance au-delà de laquelle le geste est reconnu comme horizontal ou vertical.
    static let axisLockDistance: CGFloat = 4
    /// Part de la largeur à parcourir pour changer de page.
    static let pageChangeFraction: CGFloat = 0.12
    /// Résistance au-delà de la première et de la dernière page.
    static let edgeResistance: CGFloat = 0.3

    private(set) var axis: Axis = .undecided
    /// Déplacement horizontal cumulé depuis le début du geste (positif : les doigts vont à droite).
    private(set) var translation: CGFloat = 0
    private var pendingX: CGFloat = 0
    private var pendingY: CGFloat = 0

    /// Le geste en cours déplace les pages.
    var isTracking: Bool { axis == .horizontal }

    mutating func begin() {
        axis = .undecided
        translation = 0
        pendingX = 0
        pendingY = 0
    }

    /// Mouvement des doigts ; renvoie `true` si le geste est pour les pages (l'événement est alors
    /// consommé), `false` s'il revient à la vue sous le pointeur (liste qui défile verticalement…).
    mutating func move(dx: CGFloat, dy: CGFloat) -> Bool {
        switch axis {
        case .vertical:
            return false
        case .horizontal:
            translation += dx
            return true
        case .undecided:
            pendingX += dx
            pendingY += dy
            guard max(abs(pendingX), abs(pendingY)) >= Self.axisLockDistance else { return true }
            if abs(pendingX) > abs(pendingY) {
                axis = .horizontal
                translation = pendingX
                return true
            }
            axis = .vertical
            return false
        }
    }

    /// Décalage des pages pendant le geste (avec résistance aux extrémités).
    func offset(page: Int, pageCount: Int) -> CGFloat {
        guard isTracking else { return 0 }
        let pastFirst = page <= 0 && translation > 0
        let pastLast = page >= pageCount - 1 && translation < 0
        return pastFirst || pastLast ? translation * Self.edgeResistance : translation
    }

    /// Page sur laquelle le geste se calerait s'il finissait maintenant.
    func target(page: Int, pageCount: Int, pageWidth: CGFloat) -> Int {
        guard isTracking, pageCount > 0, pageWidth > 0 else { return page }
        let threshold = pageWidth * Self.pageChangeFraction
        var target = page
        if translation <= -threshold { target += 1 } else if translation >= threshold { target -= 1 }
        return min(max(target, 0), pageCount - 1)
    }

    /// Fin du geste : page sur laquelle se caler.
    mutating func end(page: Int, pageCount: Int, pageWidth: CGFloat) -> Int {
        defer { begin() }
        return target(page: page, pageCount: pageCount, pageWidth: pageWidth)
    }
}
