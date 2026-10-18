import SwiftUI

/// Dix propositions de mascotte supplémentaires (deuxième planche).
struct MoreMascotBody: View {
    let design: MascotDesign
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat

    private var angry: Bool { mood == .angry }
    private let red = Color(red: 1, green: 0.32, blue: 0.28)

    var body: some View {
        switch design {
        case .nimbus: nimbus
        case .byte: byte
        case .sprout: sprout
        case .ember: ember
        case .moth: moth
        case .pebble: pebble
        case .orbit: orbit
        case .kiwi: kiwi
        case .ghost: ghost
        default: isle
        }
    }

    // MARK: Personnages

    /// Petit nuage : trois bosses, ventre plat, yeux sombres.
    private var nimbus: some View {
        let color = angry ? Color(red: 0.55, green: 0.58, blue: 0.68) : Color(red: 0.86, green: 0.92, blue: 1)
        return ZStack {
            ZStack {
                Circle().frame(width: size * 0.6).offset(x: -size * 0.3, y: size * 0.08)
                Circle().frame(width: size * 0.78).offset(x: size * 0.02, y: -size * 0.06)
                Circle().frame(width: size * 0.56).offset(x: size * 0.33, y: size * 0.1)
                Capsule().frame(width: size * 1.15, height: size * 0.42).offset(y: size * 0.2)
            }
            .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(red: 0.5, green: 0.7, blue: 1).opacity(0.45), radius: size * 0.12)
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: Color(red: 0.15, green: 0.2, blue: 0.35),
                       lidColor: color, eyeSize: CGSize(width: size * 0.11, height: size * 0.2), spacing: size * 0.22)
                .offset(y: size * 0.06)
            MascotMouth(mood: mood, color: Color(red: 0.15, green: 0.2, blue: 0.35), width: size * 0.13)
                .offset(y: size * 0.27)
            if angry {
                Image(systemName: "bolt.fill").font(.system(size: size * 0.22)).foregroundStyle(.yellow)
                    .offset(x: -size * 0.1, y: size * 0.55)
            }
        }
    }

    /// Écran rétro : boîtier clair, écran noir, yeux de phosphore.
    private var byte: some View {
        let phosphor = angry ? red : Color(red: 0.35, green: 1, blue: 0.55)
        return ZStack {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.92, green: 0.9, blue: 0.84), Color(red: 0.75, green: 0.72, blue: 0.66)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 1.15, height: size * 0.88)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                            .fill(Color(red: 0.04, green: 0.08, blue: 0.06))
                            .padding(size * 0.1)
                    }
                Rectangle().fill(Color(red: 0.62, green: 0.6, blue: 0.55)).frame(width: size * 0.2, height: size * 0.08)
                Capsule().fill(Color(red: 0.7, green: 0.68, blue: 0.62)).frame(width: size * 0.55, height: size * 0.08)
            }
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: phosphor, lidColor: Color(red: 0.04, green: 0.08, blue: 0.06),
                       eyeSize: CGSize(width: size * 0.11, height: size * 0.22), spacing: size * 0.26)
                .shadow(color: phosphor, radius: size * 0.06)
                .offset(y: -size * 0.1)
            MascotMouth(mood: mood, color: phosphor, width: size * 0.13)
                .offset(y: size * 0.1)
        }
    }

    /// Graine verte avec une tige et une feuille.
    private var sprout: some View {
        let colors = angry ? [Color(red: 0.95, green: 0.55, blue: 0.3), Color(red: 0.8, green: 0.3, blue: 0.15)]
                           : [Color(red: 0.62, green: 0.9, blue: 0.45), Color(red: 0.25, green: 0.65, blue: 0.3)]
        return ZStack {
            LeafShape().fill(Color(red: 0.35, green: 0.8, blue: 0.4))
                .frame(width: size * 0.36, height: size * 0.22)
                .rotationEffect(.degrees(-30))
                .offset(x: size * 0.18, y: -size * 0.56)
            Capsule().fill(Color(red: 0.3, green: 0.6, blue: 0.3)).frame(width: size * 0.05, height: size * 0.2)
                .offset(y: -size * 0.5)
            Ellipse().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.95, height: size * 0.85)
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: Color(red: 0.1, green: 0.2, blue: 0.08),
                       lidColor: colors[0], eyeSize: CGSize(width: size * 0.11, height: size * 0.2), spacing: size * 0.22)
                .offset(y: -size * 0.03)
            MascotMouth(mood: mood, color: Color(red: 0.1, green: 0.2, blue: 0.08), width: size * 0.13)
                .offset(y: size * 0.18)
        }
    }

    /// Petite flamme dansante.
    private var ember: some View {
        let colors = angry ? [Color(red: 1, green: 0.4, blue: 0.3), Color(red: 0.75, green: 0.05, blue: 0.1)]
                           : [Color(red: 1, green: 0.85, blue: 0.35), Color(red: 1, green: 0.4, blue: 0.12)]
        return ZStack {
            FlameShape()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.95, height: size * 1.15)
                .shadow(color: colors[1].opacity(0.7), radius: size * 0.15)
            FlameShape().fill(Color(red: 1, green: 0.95, blue: 0.7).opacity(0.55))
                .frame(width: size * 0.45, height: size * 0.55)
                .offset(y: size * 0.24)
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: Color(red: 0.3, green: 0.08, blue: 0),
                       lidColor: colors[1], eyeSize: CGSize(width: size * 0.1, height: size * 0.18), spacing: size * 0.2)
                .offset(y: size * 0.12)
            MascotMouth(mood: mood, color: Color(red: 0.3, green: 0.08, blue: 0), width: size * 0.12)
                .offset(y: size * 0.3)
        }
    }

    /// Papillon de nuit : ailes douces, corps duveteux, antennes plumeuses.
    private var moth: some View {
        let wing = angry ? red : Color(red: 0.78, green: 0.7, blue: 1)
        return ZStack {
            HStack(spacing: size * 0.35) {
                Ellipse().fill(wing.opacity(0.85)).frame(width: size * 0.5, height: size * 0.7).rotationEffect(.degrees(-25))
                Ellipse().fill(wing.opacity(0.85)).frame(width: size * 0.5, height: size * 0.7).rotationEffect(.degrees(25))
            }
            HStack(spacing: size * 0.25) {
                Capsule().fill(wing).frame(width: size * 0.04, height: size * 0.28).rotationEffect(.degrees(-25))
                Capsule().fill(wing).frame(width: size * 0.04, height: size * 0.28).rotationEffect(.degrees(25))
            }
            .offset(y: -size * 0.48)
            Ellipse().fill(LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 1), Color(red: 0.8, green: 0.76, blue: 0.92)],
                                          startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.62, height: size * 0.8)
            BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 0.6, isLeft: true,
                     sclera: Color(red: 0.2, green: 0.15, blue: 0.35), pupil: .white)
                .offset(x: -size * 0.12, y: -size * 0.04)
            BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 0.6, isLeft: false,
                     sclera: Color(red: 0.2, green: 0.15, blue: 0.35), pupil: .white)
                .offset(x: size * 0.12, y: -size * 0.04)
            MascotMouth(mood: mood, color: Color(red: 0.2, green: 0.15, blue: 0.35), width: size * 0.12)
                .offset(y: size * 0.18)
        }
    }

    /// Galet lisse aux yeux mi-clos, très calme.
    private var pebble: some View {
        let colors = angry ? [Color(red: 0.85, green: 0.5, blue: 0.45), Color(red: 0.6, green: 0.3, blue: 0.28)]
                           : [Color(red: 0.82, green: 0.78, blue: 0.72), Color(red: 0.55, green: 0.52, blue: 0.48)]
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 1.2, height: size * 0.8)
                .rotationEffect(.degrees(-6))
            MascotEyes(mood: mood, gaze: gaze, blink: mood == .idle ? max(blink, 0.45) : blink,
                       color: Color(red: 0.2, green: 0.18, blue: 0.16), lidColor: colors[0],
                       eyeSize: CGSize(width: size * 0.12, height: size * 0.18), spacing: size * 0.28)
            MascotMouth(mood: mood, color: Color(red: 0.2, green: 0.18, blue: 0.16), width: size * 0.13)
                .offset(y: size * 0.2)
        }
    }

    /// Petite planète turquoise et son anneau.
    private var orbit: some View {
        let colors = angry ? [Color(red: 1, green: 0.5, blue: 0.4), Color(red: 0.75, green: 0.15, blue: 0.2)]
                           : [Color(red: 0.4, green: 0.95, blue: 0.9), Color(red: 0.1, green: 0.5, blue: 0.7)]
        return ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.9)
                .shadow(color: colors[1].opacity(0.5), radius: size * 0.12)
            Ellipse().stroke(Color(red: 1, green: 0.85, blue: 0.55), lineWidth: size * 0.06)
                .frame(width: size * 1.45, height: size * 0.3)
                .rotationEffect(.degrees(-12))
                .offset(y: size * 0.22)
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: Color(red: 0.03, green: 0.15, blue: 0.2),
                       lidColor: colors[0], eyeSize: CGSize(width: size * 0.11, height: size * 0.2), spacing: size * 0.22)
                .offset(y: -size * 0.1)
            MascotMouth(mood: mood, color: Color(red: 0.03, green: 0.15, blue: 0.2), width: size * 0.12)
                .offset(y: size * 0.07)
        }
    }

    /// Petit oiseau rond, bec orange et petites pattes.
    private var kiwi: some View {
        let colors = angry ? [Color(red: 0.9, green: 0.45, blue: 0.35), Color(red: 0.65, green: 0.2, blue: 0.15)]
                           : [Color(red: 0.75, green: 0.6, blue: 0.4), Color(red: 0.5, green: 0.38, blue: 0.24)]
        return ZStack {
            HStack(spacing: size * 0.18) {
                Capsule().fill(Color(red: 1, green: 0.6, blue: 0.2)).frame(width: size * 0.06, height: size * 0.16)
                Capsule().fill(Color(red: 1, green: 0.6, blue: 0.2)).frame(width: size * 0.06, height: size * 0.16)
            }
            .offset(y: size * 0.48)
            Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.95)
            Ellipse().fill(Color(red: 0.95, green: 0.88, blue: 0.75)).frame(width: size * 0.55, height: size * 0.45)
                .offset(y: size * 0.2)
            HStack(spacing: size * 0.16) {
                BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 0.55, isLeft: true)
                BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 0.55, isLeft: false)
            }
            .offset(y: -size * 0.12)
            BeakShape().fill(Color(red: 1, green: 0.62, blue: 0.15))
                .frame(width: size * 0.18, height: size * 0.13)
                .offset(y: size * 0.03)
        }
    }

    /// Petit fantôme menthe, bas ondulé.
    private var ghost: some View {
        let colors = angry ? [Color(red: 1, green: 0.6, blue: 0.55), Color(red: 0.9, green: 0.35, blue: 0.35)]
                           : [Color(red: 0.85, green: 1, blue: 0.93), Color(red: 0.55, green: 0.9, blue: 0.78)]
        return ZStack {
            GhostShape()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.95, height: size * 1.1)
                .shadow(color: colors[1].opacity(0.6), radius: size * 0.14)
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: Color(red: 0.08, green: 0.2, blue: 0.16),
                       lidColor: colors[0], eyeSize: CGSize(width: size * 0.12, height: size * 0.22), spacing: size * 0.22)
                .offset(y: -size * 0.12)
            MascotMouth(mood: mood, color: Color(red: 0.08, green: 0.2, blue: 0.16), width: size * 0.13)
                .offset(y: size * 0.1)
        }
    }

    /// Île noire en pilule, comme une Dynamic Island vivante : liseré clair, yeux blancs.
    private var isle: some View {
        let eye = angry ? red : Color.white
        return ZStack {
            Capsule().fill(.black)
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: max(1, size * 0.03)))
                .frame(width: size * 1.35, height: size * 0.55)
            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: eye, lidColor: .black,
                       eyeSize: CGSize(width: size * 0.12, height: size * 0.24), spacing: size * 0.26)
                .shadow(color: eye.opacity(0.5), radius: size * 0.05)
            // Petite « caméra » sur le côté, comme l'encoche.
            Circle().fill(Color(red: 0.12, green: 0.14, blue: 0.22))
                .overlay(Circle().fill(Color(red: 0.3, green: 0.35, blue: 0.6)).padding(size * 0.02))
                .frame(width: size * 0.09)
                .offset(x: size * 0.48)
        }
    }
}

// MARK: - Formes

/// Feuille pointue aux deux bouts.
private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.4))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.4))
        return path
    }
}

/// Flamme : base ronde, pointe en haut légèrement penchée.
private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.58, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.68),
                      control1: CGPoint(x: rect.minX + w * 0.7, y: rect.minY + h * 0.28),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.4))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.68),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY + h * 0.06),
                      control2: CGPoint(x: rect.minX, y: rect.maxY + h * 0.06))
        path.addCurve(to: CGPoint(x: rect.minX + w * 0.58, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.42),
                      control2: CGPoint(x: rect.minX + w * 0.42, y: rect.minY + h * 0.3))
        path.closeSubpath()
        return path
    }
}

/// Bec en triangle arrondi, pointe vers le bas.
private struct BeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}

/// Fantôme : dôme en haut, trois vagues en bas.
private struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.45))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + h * 0.45), radius: w / 2,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - h * 0.08))
        let waves = 3
        for index in 0..<waves {
            let x1 = rect.maxX - w * CGFloat(index) / CGFloat(waves)
            let x2 = rect.maxX - w * CGFloat(index + 1) / CGFloat(waves)
            path.addQuadCurve(to: CGPoint(x: x2, y: rect.maxY - h * 0.08),
                              control: CGPoint(x: (x1 + x2) / 2, y: rect.maxY + h * 0.08))
        }
        path.closeSubpath()
        return path
    }
}
