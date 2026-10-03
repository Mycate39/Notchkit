import SwiftUI

/// Forme de l'encoche, animable.
///
/// - Style encoche (`earRadius > 0`) : bord supérieur droit, raccordé à l'écran par deux
///   petits congés concaves, coins inférieurs arrondis.
/// - Style pastille (`earRadius == 0`) : rectangle aux quatre coins arrondis.
struct NotchShape: Shape {
    var earRadius: CGFloat
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4)
        let left = rect.minX + ear
        let right = rect.maxX - ear
        let maxRadius = max(0, min((right - left) / 2, rect.height / 2))
        let top = ear > 0 ? 0 : min(topCornerRadius, maxRadius)
        let bottom = min(bottomCornerRadius, maxRadius)

        var path = Path()

        // Haut gauche
        if ear > 0 {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: left, y: rect.minY + ear),
                control: CGPoint(x: left, y: rect.minY)
            )
        } else {
            path.move(to: CGPoint(x: left + top, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: left, y: rect.minY),
                tangent2End: CGPoint(x: left, y: rect.maxY),
                radius: top
            )
        }

        // Côté gauche puis coin bas gauche
        path.addArc(
            tangent1End: CGPoint(x: left, y: rect.maxY),
            tangent2End: CGPoint(x: right, y: rect.maxY),
            radius: bottom
        )
        // Bas puis coin bas droit
        path.addArc(
            tangent1End: CGPoint(x: right, y: rect.maxY),
            tangent2End: CGPoint(x: right, y: rect.minY),
            radius: bottom
        )

        // Côté droit puis haut droit
        if ear > 0 {
            path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: right, y: rect.minY)
            )
        } else {
            path.addArc(
                tangent1End: CGPoint(x: right, y: rect.minY),
                tangent2End: CGPoint(x: left, y: rect.minY),
                radius: top
            )
        }

        path.closeSubpath()
        return path
    }
}
