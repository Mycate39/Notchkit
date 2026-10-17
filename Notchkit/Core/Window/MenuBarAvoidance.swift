import AppKit
import ApplicationServices

/// Évite que l'encoche (simulée ou pastille) cache les menus de l'app au premier plan.
///
/// Sur un Mac à encoche réelle, macOS réserve lui-même la place. Ailleurs, les apps ignorent
/// l'encoche de Notchkit : on lit donc la position de leurs menus (API Accessibilité publique,
/// autorisation « Accessibilité » requise) et on décale l'encoche vers la droite si besoin.
@MainActor
enum MenuBarAvoidance {
    /// Espace laissé entre le dernier menu et l'encoche.
    nonisolated static let margin: CGFloat = 14
    /// Décalage maximal (au-delà, l'encoche risquerait de couvrir les icônes de droite).
    nonisolated static let maxOffset: CGFloat = 320

    /// Bord droit des menus de l'app au premier plan, relatif au bord gauche de son écran.
    /// `nil` si l'autorisation manque ou si les menus sont illisibles.
    static func frontmostMenusRightEdge() -> CGFloat? {
        frontmostMenuSpans()?.map(\.upperBound).max()
    }

    /// Étendue horizontale de chaque menu de l'app au premier plan, relative au bord gauche
    /// de son écran. `nil` si l'autorisation manque ou si les menus sont illisibles.
    static func frontmostMenuSpans() -> [ClosedRange<CGFloat>]? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarValue, CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        else { return nil }
        let menuBar = unsafeDowncast(menuBarValue as AnyObject, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let items = childrenValue as? [AXUIElement], !items.isEmpty
        else { return nil }

        // Coordonnées globales (origine en haut à gauche de l'écran principal).
        let frames = items.compactMap(frame(of:)).filter { $0.width > 0 }
        guard let first = frames.min(by: { $0.minX < $1.minX }) else { return nil }
        // Les menus sont dessinés sur l'écran de la barre active ; on garde leur étendue
        // relative au bord gauche de cet écran (identique sur chaque écran).
        let screenMinX = NSScreen.screens.first { $0.frame.minX <= first.minX && first.minX < $0.frame.maxX }?.frame.minX ?? 0
        return frames.map { ($0.minX - screenMinX)...($0.maxX - screenMinX) }
    }

    /// Largeur maximale de chaque côté de l'activité compacte autour d'une encoche réelle, pour
    /// ne pas couvrir les menus que macOS place de part et d'autre (fonction pure, testée).
    /// La forme dépasse de l'encoche de `sideWidth + earRadius` de chaque côté ; elle reste
    /// symétrique, donc le côté le plus encombré fixe la largeur des deux.
    /// - Returns: `nil` sans contrainte, `0` si la place ne suffit plus (activité masquée),
    ///   sinon une largeur comprise entre `minimumSideWidth` et `preferred`.
    nonisolated static func compactSideWidth(menuSpans: [ClosedRange<CGFloat>]?,
                                             notchMinX: CGFloat, notchMaxX: CGFloat,
                                             preferred: CGFloat) -> CGFloat? {
        guard let menuSpans, !menuSpans.isEmpty else { return nil }
        let center = (notchMinX + notchMaxX) / 2
        let overhang = NotchLayout.earRadius + notchMargin
        var limit = CGFloat.infinity
        // Menus à gauche de l'encoche : place entre le dernier d'entre eux et l'encoche.
        if let leftEdge = menuSpans.filter({ ($0.lowerBound + $0.upperBound) / 2 < center }).map(\.upperBound).max() {
            limit = min(limit, notchMinX - leftEdge - overhang)
        }
        // Menus à droite (repoussés après l'encoche quand ils ne tiennent pas à gauche).
        if let rightEdge = menuSpans.filter({ ($0.lowerBound + $0.upperBound) / 2 >= center }).map(\.lowerBound).min() {
            limit = min(limit, rightEdge - notchMaxX - overhang)
        }
        guard limit < preferred else { return nil }
        return limit >= minimumSideWidth ? limit.rounded(.down) : 0
    }

    /// Espace laissé entre un menu et l'activité compacte, autour d'une encoche réelle.
    nonisolated static let notchMargin: CGFloat = 6
    /// En dessous, une icône ne tient plus de ce côté : l'activité compacte est masquée.
    nonisolated static let minimumSideWidth: CGFloat = 34

    /// Décalage horizontal à appliquer à l'encoche pour libérer les menus (fonction pure, testée).
    /// - Parameters:
    ///   - menusRightEdge: bord droit des menus, relatif au bord gauche de l'écran.
    ///   - centerX: centre de l'encoche, relatif au bord gauche de l'écran.
    ///   - halfWidth: demi-largeur de l'encoche repliée.
    nonisolated static func offset(menusRightEdge: CGFloat?, centerX: CGFloat, halfWidth: CGFloat) -> CGFloat {
        guard let menusRightEdge else { return 0 }
        let needed = menusRightEdge + margin - (centerX - halfWidth)
        return min(max(0, needed), maxOffset).rounded()
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeDowncast(positionValue as AnyObject, to: AXValue.self), .cgPoint, &position)
        AXValueGetValue(unsafeDowncast(sizeValue as AnyObject, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
