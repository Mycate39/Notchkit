import SwiftUI

/// Visage de l'assistant, dessiné au trait (création originale inspirée des interfaces de
/// reconnaissance faciale : quatre coins de cadrage et un visage simple).
/// - au repos : léger souffle des coins, clignements, regard qui se promène ;
/// - réfléchit : les coins tournent autour du visage, regard vers le haut ;
/// - parle : la bouche s'ouvre au rythme de la réponse ;
/// - erreur : tout passe à l'orange, bouche triste.
struct AssistantFace: View {
    enum Mood: Equatable { case idle, thinking, speaking, error }

    let mood: Mood
    var size: CGFloat = 64

    private var color: Color {
        switch mood {
        case .idle: Color(red: 0.35, green: 0.85, blue: 1)
        case .thinking: Color(red: 0.65, green: 0.55, blue: 1)
        case .speaking: Color(red: 0.3, green: 0.95, blue: 0.65)
        case .error: .orange
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, canvasSize in
                draw(in: &canvas, size: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: mood)
        .accessibilityLabel(Text("Assistant"))
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let s = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let line = max(1.5, s * 0.055)
        let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        let shading = GraphicsContext.Shading.color(color)

        // Halo doux.
        canvas.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.12))
            layer.fill(Path(ellipseIn: CGRect(x: center.x - s * 0.28, y: center.y - s * 0.28, width: s * 0.56, height: s * 0.56)),
                       with: .color(color.opacity(0.25)))
        }

        // Coins de cadrage : ils « respirent » au repos et tournent quand l'assistant réfléchit.
        let breathe = (sin(time * 2.2) * 0.5 + 0.5) * s * 0.025
        let inset = s * 0.08 + breathe
        let frame = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        let corner = s * 0.16
        let arm = s * 0.12
        var brackets = Path()
        for (index, point) in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                               CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)].enumerated() {
            let horizontal: CGFloat = index == 0 || index == 3 ? 1 : -1
            let vertical: CGFloat = index < 2 ? 1 : -1
            brackets.move(to: CGPoint(x: point.x, y: point.y + vertical * (corner + arm)))
            brackets.addLine(to: CGPoint(x: point.x, y: point.y + vertical * corner))
            brackets.addQuadCurve(to: CGPoint(x: point.x + horizontal * corner, y: point.y), control: point)
            brackets.addLine(to: CGPoint(x: point.x + horizontal * (corner + arm), y: point.y))
        }
        if mood == .thinking {
            let angle = Angle.radians(time * 1.6)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle.radians)
                .translatedBy(x: -center.x, y: -center.y)
            canvas.stroke(brackets.applying(transform), with: shading, style: style)
        } else {
            canvas.stroke(brackets, with: shading, style: style)
        }

        // Regard.
        let look: CGSize = switch mood {
        case .thinking: CGSize(width: s * 0.03, height: -s * 0.04)
        case .error: CGSize(width: 0, height: s * 0.015)
        default: CGSize(width: sin(time * 0.7) * s * 0.03, height: cos(time * 0.5) * s * 0.012)
        }
        // Clignement toutes les ~3,5 s.
        let blinkPhase = time.truncatingRemainder(dividingBy: 3.5)
        let blink = blinkPhase < 0.14 ? max(0.08, abs(blinkPhase - 0.07) / 0.07) : 1

        // Yeux : deux petits traits verticaux.
        let eyeY = center.y - s * 0.06 + look.height
        let eyeHalf = s * 0.06 * blink
        var eyes = Path()
        for side in [-1.0, 1.0] {
            let x = center.x + side * s * 0.12 + look.width
            eyes.move(to: CGPoint(x: x, y: eyeY - eyeHalf))
            eyes.addLine(to: CGPoint(x: x, y: eyeY + eyeHalf))
        }
        canvas.stroke(eyes, with: shading, style: StrokeStyle(lineWidth: line * 1.15, lineCap: .round))

        // Bouche.
        let mouthY = center.y + s * 0.13
        let mouthHalf = s * 0.11
        var mouth = Path()
        switch mood {
        case .speaking:
            // Alterne entre sourire et bouche ouverte, comme des syllabes.
            let open = (sin(time * 13) * 0.5 + 0.5) * (sin(time * 2.9) * 0.3 + 0.7)
            let rect = CGRect(x: center.x - mouthHalf * (0.75 - 0.25 * open), y: mouthY - s * 0.02,
                              width: mouthHalf * 2 * (0.75 - 0.25 * open), height: s * (0.03 + 0.09 * open))
            mouth.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.width / 2, height: rect.height / 2))
        case .thinking:
            mouth.move(to: CGPoint(x: center.x - mouthHalf * 0.5, y: mouthY))
            mouth.addLine(to: CGPoint(x: center.x + mouthHalf * 0.5, y: mouthY))
        case .error:
            mouth.move(to: CGPoint(x: center.x - mouthHalf, y: mouthY + s * 0.03))
            mouth.addQuadCurve(to: CGPoint(x: center.x + mouthHalf, y: mouthY + s * 0.03),
                               control: CGPoint(x: center.x, y: mouthY - s * 0.05))
        case .idle:
            mouth.move(to: CGPoint(x: center.x - mouthHalf, y: mouthY - s * 0.02))
            mouth.addQuadCurve(to: CGPoint(x: center.x + mouthHalf, y: mouthY - s * 0.02),
                               control: CGPoint(x: center.x, y: mouthY + s * 0.08))
        }
        canvas.stroke(mouth, with: shading, style: style)

        // Petit point lumineux au-dessus du visage (signature de l'assistant) : il pulse.
        let pulse = sin(time * (mood == .speaking ? 8 : 2.5)) * 0.5 + 0.5
        let dotSize = s * (0.045 + 0.02 * pulse)
        canvas.fill(Path(ellipseIn: CGRect(x: center.x - dotSize / 2, y: frame.minY + s * 0.06 - dotSize / 2,
                                           width: dotSize, height: dotSize)),
                    with: .color(color.opacity(0.6 + 0.4 * pulse)))
    }
}
