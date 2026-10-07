import SwiftUI

/// Disposition en lignes qui passent à la ligne quand la largeur est atteinte (étiquettes, pastilles).
/// Chaque élément garde sa taille idéale : il n'est jamais comprimé.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.arrange(sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing, lineSpacing: lineSpacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = Self.arrange(sizes, maxWidth: bounds.width, spacing: spacing, lineSpacing: lineSpacing).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    /// Calcule l'origine de chaque élément et la taille totale. Un élément plus large que `maxWidth`
    /// occupe seul sa ligne. Les éléments d'une ligne sont centrés verticalement.
    static func arrange(_ sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat)
        -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var lines: [[Int]] = [[]]
        var x: CGFloat = 0

        // Répartition en lignes.
        for (index, size) in sizes.enumerated() {
            if !lines[lines.count - 1].isEmpty, x + spacing + size.width > maxWidth {
                lines.append([])
                x = 0
            }
            x += (lines[lines.count - 1].isEmpty ? 0 : spacing) + size.width
            lines[lines.count - 1].append(index)
        }

        // Positions, ligne par ligne.
        origins = Array(repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        var width: CGFloat = 0
        for line in lines where !line.isEmpty {
            let lineHeight = line.map { sizes[$0].height }.max() ?? 0
            var lineX: CGFloat = 0
            for index in line {
                origins[index] = CGPoint(x: lineX, y: y + (lineHeight - sizes[index].height) / 2)
                lineX += sizes[index].width + spacing
            }
            width = max(width, lineX - spacing)
            y += lineHeight + lineSpacing
        }
        let height = max(0, y - lineSpacing)
        return (origins, CGSize(width: sizes.isEmpty ? 0 : width, height: sizes.isEmpty ? 0 : height))
    }
}
