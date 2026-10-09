import CoreGraphics

/// Zone d'ancrage d'une fenêtre : moitiés, tiers, quarts ou plein écran.
enum SnapZone: String, CaseIterable, Identifiable, Sendable {
    case leftHalf, rightHalf, maximize
    case leftThird, centerThird, rightThird
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    /// Rangées affichées sous l'encoche.
    static let rows: [[SnapZone]] = [
        [.leftHalf, .rightHalf, .maximize, .topLeft, .topRight],
        [.leftThird, .centerThird, .rightThird, .bottomLeft, .bottomRight],
    ]

    /// Part de l'écran (0…1) occupée par la zone, origine en haut à gauche.
    var unitRect: CGRect {
        switch self {
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .leftThird: CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        }
    }

    /// Cadre de la fenêtre en coordonnées d'accessibilité (origine en haut à gauche de l'écran principal).
    /// `visibleFrame` : zone utile de l'écran (sans barre des menus ni Dock), coordonnées AppKit (origine en bas).
    /// `primaryHeight` : hauteur de l'écran principal, qui sert de référence au retournement vertical.
    func frame(visibleFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let unit = unitRect
        let x = visibleFrame.minX + unit.minX * visibleFrame.width
        let width = unit.width * visibleFrame.width
        let height = unit.height * visibleFrame.height
        // Haut de la zone en coordonnées AppKit, puis retournement en coordonnées AX.
        let topAppKit = visibleFrame.maxY - unit.minY * visibleFrame.height
        return CGRect(x: x.rounded(), y: (primaryHeight - topAppKit).rounded(),
                      width: width.rounded(), height: height.rounded())
    }

    /// Déclenchement : pointeur à moins de `margin` points du haut de l'écran.
    static func isNearTop(pointerY: CGFloat, screenMaxY: CGFloat, margin: CGFloat = 60) -> Bool {
        screenMaxY - pointerY <= margin
    }
}
