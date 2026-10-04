import SwiftUI

/// Visage animé de l'assistant (personnage original) : une bille lumineuse aux grands yeux.
/// - au repos : clignements réguliers, regard qui se promène ;
/// - réfléchit : yeux tournés vers le haut, petits points qui s'allument ;
/// - parle : la bouche s'ouvre et se ferme au rythme de la réponse ;
/// - erreur : sourcils froncés.
struct AssistantFace: View {
    enum Mood: Equatable { case idle, thinking, speaking, error }

    let mood: Mood
    var size: CGFloat = 64

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, canvasSize in
                draw(in: &canvas, size: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("Assistant"))
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let s = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Petit flottement vertical.
        let bob = sin(time * 2) * s * 0.02
        let headRect = CGRect(x: center.x - s * 0.44, y: center.y - s * 0.42 + bob, width: s * 0.88, height: s * 0.84)

        // Tête : dégradé doux, halo selon l'humeur.
        let glow: Color = switch mood {
        case .idle: .cyan
        case .thinking: .purple
        case .speaking: .mint
        case .error: .orange
        }
        canvas.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.08))
            layer.fill(Path(ellipseIn: headRect.insetBy(dx: -s * 0.02, dy: -s * 0.02)), with: .color(glow.opacity(0.45)))
        }
        canvas.fill(
            Path(roundedRect: headRect, cornerRadius: s * 0.38),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.95), Color(red: 0.58, green: 0.32, blue: 0.9)]),
                startPoint: CGPoint(x: headRect.minX, y: headRect.minY),
                endPoint: CGPoint(x: headRect.maxX, y: headRect.maxY)
            )
        )

        // Regard : se promène au repos, vers le haut quand l'assistant réfléchit.
        let look: CGSize = switch mood {
        case .thinking: CGSize(width: s * 0.04, height: -s * 0.05)
        case .error: CGSize(width: 0, height: s * 0.02)
        default: CGSize(width: sin(time * 0.7) * s * 0.035, height: cos(time * 0.5) * s * 0.015)
        }

        // Clignement toutes les ~3,5 s.
        let blinkPhase = time.truncatingRemainder(dividingBy: 3.5)
        let blink = blinkPhase < 0.12 ? max(0.1, abs(blinkPhase - 0.06) / 0.06) : 1

        let eyeY = headRect.minY + headRect.height * 0.42
        for side in [-1.0, 1.0] {
            let eyeCenter = CGPoint(x: center.x + side * s * 0.16 + look.width, y: eyeY + look.height)
            let eyeSize = CGSize(width: s * 0.13, height: s * 0.19 * blink)
            let eye = CGRect(x: eyeCenter.x - eyeSize.width / 2, y: eyeCenter.y - eyeSize.height / 2,
                             width: eyeSize.width, height: eyeSize.height)
            canvas.fill(Path(ellipseIn: eye), with: .color(.white))
            // Reflet.
            if blink > 0.6 {
                let shine = CGRect(x: eye.minX + eye.width * 0.2, y: eye.minY + eye.height * 0.15,
                                   width: eye.width * 0.3, height: eye.width * 0.3)
                canvas.fill(Path(ellipseIn: shine), with: .color(Color(red: 0.35, green: 0.42, blue: 0.95)))
            }
            // Sourcils froncés en cas d'erreur.
            if mood == .error {
                var brow = Path()
                brow.move(to: CGPoint(x: eyeCenter.x - side * s * 0.08, y: eye.minY - s * 0.06))
                brow.addLine(to: CGPoint(x: eyeCenter.x + side * s * 0.06, y: eye.minY - s * 0.02))
                canvas.stroke(brow, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
            }
        }

        // Bouche.
        let mouthY = headRect.minY + headRect.height * 0.72
        var mouth = Path()
        switch mood {
        case .speaking:
            // Ouverture variable, comme une syllabe.
            let open = (sin(time * 14) * 0.5 + 0.5) * (sin(time * 3.1) * 0.3 + 0.7)
            let rect = CGRect(x: center.x - s * 0.08, y: mouthY - s * 0.03, width: s * 0.16, height: s * (0.03 + 0.09 * open))
            canvas.fill(Path(roundedRect: rect, cornerRadius: s * 0.05), with: .color(.white))
        case .thinking:
            mouth.move(to: CGPoint(x: center.x - s * 0.05, y: mouthY))
            mouth.addLine(to: CGPoint(x: center.x + s * 0.05, y: mouthY))
            canvas.stroke(mouth, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
            // Points de réflexion.
            for index in 0..<3 {
                let active = Int(time * 3) % 3 == index
                // Points en diagonale, dans le coin supérieur droit (à l'intérieur du cadre).
                let dot = CGRect(x: size.width - s * 0.26 + CGFloat(index) * s * 0.08,
                                 y: s * 0.16 - CGFloat(index) * s * 0.06,
                                 width: s * 0.06, height: s * 0.06)
                canvas.fill(Path(ellipseIn: dot), with: .color(.white.opacity(active ? 0.95 : 0.35)))
            }
        case .error:
            mouth.move(to: CGPoint(x: center.x - s * 0.08, y: mouthY + s * 0.03))
            mouth.addQuadCurve(to: CGPoint(x: center.x + s * 0.08, y: mouthY + s * 0.03), control: CGPoint(x: center.x, y: mouthY - s * 0.04))
            canvas.stroke(mouth, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
        case .idle:
            mouth.move(to: CGPoint(x: center.x - s * 0.09, y: mouthY - s * 0.01))
            mouth.addQuadCurve(to: CGPoint(x: center.x + s * 0.09, y: mouthY - s * 0.01), control: CGPoint(x: center.x, y: mouthY + s * 0.07))
            canvas.stroke(mouth, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
        }
    }
}
