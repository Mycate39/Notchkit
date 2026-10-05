import SwiftUI

/// Étoile de Claude : rayons effilés, de longueurs légèrement irrégulières, partant du centre.
/// Dessin original inspiré de l'identité de Claude (pas une copie du logo officiel).
struct ClaudeMarkShape: Shape {
    /// Longueur relative de chaque rayon (irrégulière, comme tracée à la main).
    private static let lengths: [CGFloat] = [1, 0.8, 0.94, 0.76, 0.98, 0.84, 0.92, 0.74, 1, 0.82, 0.9, 0.78]
    /// Petits décalages d'angle (en fraction d'intervalle) pour éviter une symétrie trop parfaite.
    private static let jitter: [CGFloat] = [0, 0.08, -0.05, 0.06, -0.04, 0.05, 0.02, -0.07, 0.04, -0.03, 0.07, -0.06]

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxLength = side * 0.5
        let baseHalfWidth = side * 0.062
        let tipRadius = side * 0.036
        let count = Self.lengths.count

        var path = Path()
        for index in 0..<count {
            let length = maxLength * Self.lengths[index] - tipRadius
            // Rayon vertical vers le haut, puis tourné autour du centre.
            var ray = Path()
            ray.move(to: CGPoint(x: -baseHalfWidth, y: 0))
            ray.addLine(to: CGPoint(x: -tipRadius, y: -length))
            ray.addArc(center: CGPoint(x: 0, y: -length), radius: tipRadius,
                       startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            ray.addLine(to: CGPoint(x: baseHalfWidth, y: 0))
            ray.addArc(center: .zero, radius: baseHalfWidth, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            ray.closeSubpath()

            let angle = (CGFloat(index) + Self.jitter[index]) / CGFloat(count) * 2 * .pi
            let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
            path.addPath(ray, transform: transform)
        }
        return path
    }
}

enum ClaudeMark {
    /// Nom de « symbole » réservé aux modules qui utilisent l'étoile de Claude.
    static let symbolName = "notchkit.claude"
    /// Terre cuite, couleur de Claude.
    static let color = Color(red: 0.85, green: 0.47, blue: 0.34)
    /// Fond crème des icônes.
    static let background = Color(red: 0.96, green: 0.94, blue: 0.9)
}

/// Icône d'un module : symbole SF, ou dessin propre à Notchkit (étoile de Claude).
struct ModuleIcon: View {
    let symbol: String

    var body: some View {
        if symbol == ClaudeMark.symbolName {
            ClaudeMarkShape()
                .aspectRatio(1, contentMode: .fit)
                .frame(minWidth: 10, minHeight: 10)
        } else {
            Image(systemName: symbol)
        }
    }
}
