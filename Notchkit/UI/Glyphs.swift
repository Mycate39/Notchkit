import SwiftUI

// Icônes au trait de Notchkit (créations originales, dessinées en code).
// Toutes sont définies dans un carré unité (0…1) et s'adaptent à leur cadre.

/// Éclair de charge.
struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.60, y: 0.04), CGPoint(x: 0.20, y: 0.56), CGPoint(x: 0.47, y: 0.56),
            CGPoint(x: 0.40, y: 0.96), CGPoint(x: 0.80, y: 0.44), CGPoint(x: 0.53, y: 0.44),
        ]
        var path = Path()
        path.addLines(points.map { rect.point(at: $0) })
        path.closeSubpath()
        return path
    }
}

/// Éclair plein de la jauge, aux angles légèrement adoucis.
struct BatteryBoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.66, y: 0.00), CGPoint(x: 0.00, y: 0.58), CGPoint(x: 0.45, y: 0.58),
            CGPoint(x: 0.34, y: 1.00), CGPoint(x: 1.00, y: 0.42), CGPoint(x: 0.55, y: 0.42),
        ]
        var path = Path()
        path.addLines(points.map { rect.point(at: $0) })
        path.closeSubpath()
        return path.strokedPath(StrokeStyle(lineWidth: rect.width * 0.08, lineJoin: .round)).union(path)
    }
}

/// Prise secteur : deux broches, un corps arrondi et le câble.
struct PlugShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Broches.
        for x in [0.37, 0.63] {
            path.move(to: rect.point(at: CGPoint(x: x, y: 0.05)))
            path.addLine(to: rect.point(at: CGPoint(x: x, y: 0.27)))
        }
        // Corps : haut droit, bas en ogive.
        path.move(to: rect.point(at: CGPoint(x: 0.22, y: 0.27)))
        path.addLine(to: rect.point(at: CGPoint(x: 0.78, y: 0.27)))
        path.addLine(to: rect.point(at: CGPoint(x: 0.78, y: 0.45)))
        path.addQuadCurve(to: rect.point(at: CGPoint(x: 0.5, y: 0.72)), control: rect.point(at: CGPoint(x: 0.78, y: 0.72)))
        path.addQuadCurve(to: rect.point(at: CGPoint(x: 0.22, y: 0.45)), control: rect.point(at: CGPoint(x: 0.22, y: 0.72)))
        path.closeSubpath()
        // Câble.
        path.move(to: rect.point(at: CGPoint(x: 0.5, y: 0.72)))
        path.addLine(to: rect.point(at: CGPoint(x: 0.5, y: 0.95)))
        return path
    }
}

/// Note de musique : tête ronde, hampe et crochet.
struct MusicNoteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let head = CGRect(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.60,
                          width: rect.width * 0.26, height: rect.height * 0.24)
        path.addEllipse(in: head)
        path.move(to: rect.point(at: CGPoint(x: 0.52, y: 0.72)))
        path.addLine(to: rect.point(at: CGPoint(x: 0.52, y: 0.14)))
        path.addQuadCurve(to: rect.point(at: CGPoint(x: 0.76, y: 0.40)), control: rect.point(at: CGPoint(x: 0.56, y: 0.30)))
        return path
    }
}

private extension CGRect {
    /// Point exprimé en coordonnées relatives (0…1) du rectangle.
    func point(at unit: CGPoint) -> CGPoint {
        CGPoint(x: minX + unit.x * width, y: minY + unit.y * height)
    }
}

/// Affiche une icône au trait, avec une épaisseur proportionnelle à sa taille.
struct LineGlyph<S: Shape>: View {
    let shape: S
    /// Épaisseur du trait, relative au côté de l'icône.
    var weight: CGFloat = 0.1

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            shape
                .stroke(style: StrokeStyle(lineWidth: max(1, side * weight), lineCap: .round, lineJoin: .round))
                .padding(side * weight / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Pochette par défaut : dégradé sombre et note au trait.
struct DefaultArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                LineGlyph(shape: MusicNoteShape(), weight: 0.09)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: side * 0.56, height: side * 0.56)
            }
        }
    }
}
