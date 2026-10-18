import SwiftUI

/// Dix visages inspirés du pictogramme de Face ID (quatrième planche) : coins en équerre,
/// yeux en traits, nez en crochet et sourire, déclinés en plusieurs styles.
struct FaceIDMascotBody: View {
    let design: MascotDesign
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    private let red = Color(red: 1, green: 0.32, blue: 0.28)

    /// Couleur du trait selon l'humeur (comme Face ID : vert réussi, rouge refusé).
    private func tint(_ base: Color) -> Color {
        switch mood {
        case .happy: green
        case .angry: red
        case .waiting: StandBy.amber
        default: base
        }
    }

    var body: some View {
        let side = size * 1.0
        ZStack {
            background
            Canvas { context, canvasSize in
                draw(in: &context, rect: CGRect(origin: .zero, size: canvasSize))
            }
            .frame(width: side, height: side)
            .shadow(color: glowColor, radius: glowColor == .clear ? 0 : size * 0.06)
        }
        .frame(width: side * 1.3, height: side * 1.2)
    }

    // MARK: Fond propre à chaque style

    @ViewBuilder
    private var background: some View {
        switch design {
        case .faceBlock:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Color(red: 0.08, green: 0.08, blue: 0.1))
                .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: max(1, size * 0.02)))
                .frame(width: size * 1.05, height: size * 1.05)
        case .faceGlass:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: mood == .angry ? [red, Color(red: 0.6, green: 0.1, blue: 0.2)]
                                                            : [Color(red: 0.35, green: 0.65, blue: 1), Color(red: 0.35, green: 0.3, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: max(1, size * 0.02)))
                .frame(width: size * 1.05, height: size * 1.05)
                .shadow(color: Color(red: 0.35, green: 0.4, blue: 1).opacity(0.5), radius: size * 0.1)
        case .faceHalo:
            // Anneau de traits, comme l'écran de configuration de Face ID.
            ZStack {
                ForEach(0..<48, id: \.self) { index in
                    Capsule()
                        .fill(index % 48 < haloFill ? tint(Color(red: 0.3, green: 0.85, blue: 0.55)) : .white.opacity(0.18))
                        .frame(width: size * 0.025, height: size * 0.09)
                        .offset(y: -size * 0.58)
                        .rotationEffect(.degrees(Double(index) / 48 * 360))
                }
            }
        case .faceMesh:
            ZStack {
                ForEach(1..<4, id: \.self) { index in
                    Ellipse().stroke(.white.opacity(0.14), lineWidth: max(0.5, size * 0.01))
                        .frame(width: size * 1.1 * CGFloat(index) / 3, height: size * 1.1)
                    Ellipse().stroke(.white.opacity(0.14), lineWidth: max(0.5, size * 0.01))
                        .frame(width: size * 1.1, height: size * 1.1 * CGFloat(index) / 3)
                }
            }
        default:
            EmptyView()
        }
    }

    /// Part de l'anneau allumée (Halo) : il se remplit au fil des humeurs.
    private var haloFill: Int {
        switch mood {
        case .idle: 0
        case .working: 20
        case .waiting: 34
        case .happy, .angry: 48
        }
    }

    private var glowColor: Color {
        switch design {
        case .faceNeon: tint(Color(red: 1, green: 0.3, blue: 0.85))
        case .faceScan, .faceDots: tint(Color(red: 0.3, green: 0.9, blue: 1)).opacity(0.7)
        default: .clear
        }
    }

    // MARK: Tracé du visage

    private struct Style {
        var color: Color
        var line: CGFloat
        var brackets: Bool = true
        var bracketColor: Color?
        var dotted = false
        /// Zone du visage dans le carré (marges).
        var inset: CGFloat = 0.06
    }

    private var style: Style {
        let s = size
        switch design {
        case .faceClassic: return Style(color: tint(.white), line: s * 0.055)
        case .faceScan: return Style(color: tint(Color(red: 0.3, green: 0.9, blue: 1)), line: s * 0.045)
        case .faceDots: return Style(color: tint(Color(red: 0.3, green: 0.9, blue: 1)), line: s * 0.06, dotted: true)
        case .faceNeon: return Style(color: tint(Color(red: 1, green: 0.45, blue: 0.9)), line: s * 0.05)
        case .faceMesh: return Style(color: tint(.white), line: s * 0.05, brackets: false, inset: 0.12)
        case .faceHalo: return Style(color: tint(.white), line: s * 0.05, brackets: false, inset: 0.14)
        case .faceBlock: return Style(color: tint(.white), line: s * 0.07, brackets: false, inset: 0.14)
        case .faceGlass: return Style(color: .white, line: s * 0.065, brackets: false, inset: 0.14)
        case .faceMini: return Style(color: tint(StandBy.amber), line: s * 0.09, brackets: false, inset: 0.1)
        default: return Style(color: .white, line: s * 0.05, bracketColor: tint(StandBy.amber))
        }
    }

    private func draw(in context: inout GraphicsContext, rect: CGRect) {
        let style = style
        let face = rect.insetBy(dx: rect.width * style.inset, dy: rect.height * style.inset)
        var stroke = StrokeStyle(lineWidth: style.line, lineCap: .round, lineJoin: .round)
        if style.dotted { stroke.dash = [0.01, style.line * 1.6] }

        if style.brackets {
            context.stroke(brackets(in: face), with: .color(style.bracketColor ?? style.color), style: stroke)
        }
        // Encoche au bord supérieur (Notchy).
        if design == .faceNotch {
            let notch = CGRect(x: face.midX - face.width * 0.16, y: face.minY - style.line * 0.2,
                               width: face.width * 0.32, height: face.height * 0.1)
            context.fill(Path(roundedRect: notch, cornerRadius: notch.height / 2), with: .color(.black))
            context.stroke(Path(roundedRect: notch, cornerRadius: notch.height / 2), with: .color(.white.opacity(0.4)),
                           lineWidth: max(1, style.line * 0.3))
        }

        let point = { (x: CGFloat, y: CGFloat) in CGPoint(x: face.minX + face.width * x, y: face.minY + face.height * y) }
        let dx = gaze.width * 0.05, dy = gaze.height * 0.04
        var features = Path()

        // Yeux.
        for (index, x) in [0.29, 0.71].enumerated() {
            let cx = x + dx
            switch mood {
            case .happy:
                features.move(to: point(cx - 0.07, 0.38 + dy))
                features.addQuadCurve(to: point(cx + 0.07, 0.38 + dy), control: point(cx, 0.26 + dy))
            case .angry:
                let inner: CGFloat = index == 0 ? 0.05 : -0.05
                features.move(to: point(cx - inner, 0.3 + dy))
                features.addLine(to: point(cx + inner, 0.42 + dy))
            default:
                let half: CGFloat = switch mood {
                case .working: 0.015
                case .waiting: 0.09
                default: 0.065 * (1 - blink * 0.85)
                }
                features.move(to: point(cx, 0.36 + dy - half))
                features.addLine(to: point(cx, 0.36 + dy + half))
            }
        }

        // Nez en crochet.
        if mood != .happy {
            features.move(to: point(0.5, 0.33))
            features.addLine(to: point(0.5, 0.5))
            features.addQuadCurve(to: point(0.44, 0.54), control: point(0.5, 0.54))
        }

        // Bouche.
        switch mood {
        case .happy:
            features.move(to: point(0.28, 0.66))
            features.addQuadCurve(to: point(0.72, 0.66), control: point(0.5, 0.88))
        case .waiting:
            features.addEllipse(in: CGRect(origin: point(0.45, 0.68), size: CGSize(width: face.width * 0.1, height: face.height * 0.1)))
        case .angry:
            features.move(to: point(0.34, 0.8))
            features.addQuadCurve(to: point(0.66, 0.8), control: point(0.5, 0.68))
        case .working:
            features.move(to: point(0.36, 0.74))
            features.addLine(to: point(0.64, 0.74))
        case .idle:
            features.move(to: point(0.3, 0.7))
            features.addQuadCurve(to: point(0.7, 0.7), control: point(0.5, 0.84))
        }
        context.stroke(features, with: .color(style.color), style: stroke)

        // Balayage : trait lumineux horizontal (Scan) pendant le travail et au repos.
        if design == .faceScan, mood == .working || mood == .idle {
            let y = face.minY + face.height * (mood == .working ? 0.55 : 0.3)
            var scan = Path()
            scan.move(to: CGPoint(x: face.minX + face.width * 0.08, y: y))
            scan.addLine(to: CGPoint(x: face.maxX - face.width * 0.08, y: y))
            context.stroke(scan, with: .color(style.color.opacity(0.55)), lineWidth: max(1, style.line * 0.4))
        }
    }

    /// Quatre coins en équerre arrondis, comme le pictogramme Face ID.
    private func brackets(in rect: CGRect) -> Path {
        let length = rect.width * 0.24
        let radius = rect.width * 0.14
        var path = Path()
        // Haut gauche.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // Haut droit.
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // Bas droit.
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // Bas gauche.
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}
