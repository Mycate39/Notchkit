import SwiftUI

/// Humeur de la mascotte : elle reflète l'état des agents (au repos, au travail, en attente d'une
/// réponse, tâche terminée) et réagit quand on la taquine.
enum MascotMood: CaseIterable {
    case idle, working, waiting, happy, angry
}

/// Mascottes proposées ; l'utilisateur choisit la sienne dans les réglages (Apparence).
enum MascotDesign: String, CaseIterable, Codable, Sendable {
    /// Petit bloc gris sombre aux yeux ambre, cousin de l'encoche.
    case pip
    /// Boule de lumière ambre avec une antenne.
    case lumen
    /// Goutte gélatineuse rose et violette aux grands yeux.
    case bloop
    /// Petit nuage bleu pâle.
    case nimbus
    /// Écran rétro aux yeux de phosphore vert.
    case byte
    /// Graine verte avec une feuille.
    case sprout
    /// Petite flamme.
    case ember
    /// Papillon de nuit duveteux.
    case moth
    /// Galet lisse et paisible.
    case pebble
    /// Planète à anneau.
    case orbit
    /// Petit oiseau rond.
    case kiwi
    /// Fantôme menthe.
    case ghost
    /// Île noire, cousine de la Dynamic Island.
    case isle
    // Petits robots (troisième planche).
    case bolt, cubo, dome, wheelie, tin, visor, spark, mono, chip, hover
    // Visages inspirés de Face ID (quatrième planche).
    case faceClassic, faceScan, faceDots, faceNeon, faceMesh, faceHalo, faceBlock, faceGlass, faceMini, faceNotch

    /// Les trois premières propositions.
    static let firstBoard: [MascotDesign] = [.pip, .lumen, .bloop]
    /// Les dix suivantes.
    static let secondBoard: [MascotDesign] = [.nimbus, .byte, .sprout, .ember, .moth, .pebble, .orbit, .kiwi, .ghost, .isle]
    /// Les dix petits robots.
    static let robots: [MascotDesign] = [.bolt, .cubo, .dome, .wheelie, .tin, .visor, .spark, .mono, .chip, .hover]
    /// Les dix visages façon Face ID.
    static let faces: [MascotDesign] = [.faceClassic, .faceScan, .faceDots, .faceNeon, .faceMesh,
                                        .faceHalo, .faceBlock, .faceGlass, .faceMini, .faceNotch]
    /// Toutes les propositions, dans l'ordre des planches.
    static let allBoards: [MascotDesign] = firstBoard + secondBoard + robots + faces

    var name: String {
        switch self {
        case .pip: "Pip"
        case .lumen: "Lumen"
        case .bloop: "Bloop"
        case .nimbus: "Nimbus"
        case .byte: "Byte"
        case .sprout: "Sprout"
        case .ember: "Ember"
        case .moth: "Moth"
        case .pebble: "Pebble"
        case .orbit: "Orbit"
        case .kiwi: "Kiwi"
        case .ghost: "Boo"
        case .isle: "Isle"
        case .bolt: "Bolt"
        case .cubo: "Cubo"
        case .dome: "Dôme"
        case .wheelie: "Wheelie"
        case .tin: "Tin"
        case .visor: "Visor"
        case .spark: "Spark"
        case .mono: "Mono"
        case .chip: "Chip"
        case .hover: "Hover"
        case .faceClassic: "Face"
        case .faceScan: "Scan"
        case .faceDots: "Dots"
        case .faceNeon: "Neon"
        case .faceMesh: "Mesh"
        case .faceHalo: "Halo"
        case .faceBlock: "Block"
        case .faceGlass: "Glass"
        case .faceMini: "Mini"
        case .faceNotch: "Notchy"
        }
    }
}

/// Mascotte de Notchkit, dessinée en formes vectorielles (nette à toutes les tailles).
struct MascotView: View {
    var design: MascotDesign
    var mood: MascotMood = .idle
    /// Direction du regard, de -1 à 1 sur chaque axe.
    var gaze: CGSize = .zero
    /// Fermeture des paupières : 0 ouvertes, 1 fermées.
    var blink: CGFloat = 0
    /// Hauteur de référence du personnage.
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            switch design {
            case .pip: PipBody(mood: mood, gaze: gaze, blink: blink, size: size)
            case .lumen: LumenBody(mood: mood, gaze: gaze, blink: blink, size: size)
            case .bloop: BloopBody(mood: mood, gaze: gaze, blink: blink, size: size)
            case .faceClassic, .faceScan, .faceDots, .faceNeon, .faceMesh, .faceHalo, .faceBlock, .faceGlass, .faceMini, .faceNotch:
                FaceIDMascotBody(design: design, mood: mood, gaze: gaze, blink: blink, size: size)
            case .bolt, .cubo, .dome, .wheelie, .tin, .visor, .spark, .mono, .chip, .hover:
                RobotMascotBody(design: design, mood: mood, gaze: gaze, blink: blink, size: size)
                    .offset(y: mood == .happy ? -size * 0.06 : 0)
            default: MoreMascotBody(design: design, mood: mood, gaze: gaze, blink: blink, size: size)
                .offset(y: mood == .happy ? -size * 0.06 : 0)
            }
        }
        .frame(width: size * 1.5, height: size * 1.3)
        .overlay(alignment: .topTrailing) {
            MoodBadge(mood: mood, size: size * 0.32)
                .offset(x: -size * 0.02, y: size * 0.08)
        }
    }
}

// MARK: - Pip

/// Bloc arrondi gris très sombre, petites oreilles, yeux ambre lumineux.
private struct PipBody: View {
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat

    private var bodyColor: Color { Color(red: 0.13, green: 0.13, blue: 0.15) }
    private var amber: Color { mood == .angry ? Color(red: 1, green: 0.36, blue: 0.3) : StandBy.amber }

    var body: some View {
        let width = size * 1.25
        let height = size * 0.92
        ZStack {
            // Oreilles : deux petites bosses arrondies.
            HStack(spacing: width * 0.42) {
                Capsule().fill(bodyColor).frame(width: size * 0.2, height: size * 0.3)
                    .rotationEffect(.degrees(-18))
                Capsule().fill(bodyColor).frame(width: size * 0.2, height: size * 0.3)
                    .rotationEffect(.degrees(18))
            }
            .offset(y: -height * 0.5)

            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.23), bodyColor],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: max(1, size * 0.02))
                }
                .frame(width: width, height: height)

            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: amber, lidColor: bodyColor,
                       eyeSize: CGSize(width: size * 0.15, height: size * 0.3), spacing: size * 0.3)
                .shadow(color: amber.opacity(0.7), radius: size * 0.08)
                .offset(y: -size * 0.03)

            MascotMouth(mood: mood, color: amber.opacity(0.85), width: size * 0.16)
                .offset(y: size * 0.24)
        }
        .offset(y: mood == .happy ? -size * 0.06 : 0)
    }
}

// MARK: - Lumen

/// Boule ambre qui rayonne doucement, petite antenne lumineuse, joues rosées.
private struct LumenBody: View {
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat

    private var glow: Color { mood == .angry ? Color(red: 1, green: 0.35, blue: 0.25) : StandBy.amber }

    var body: some View {
        let diameter = size * 1.0
        ZStack {
            // Antenne : une tige fine et une perle lumineuse.
            VStack(spacing: 0) {
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.5))
                    .frame(width: size * 0.13, height: size * 0.13)
                    .shadow(color: glow, radius: size * 0.08)
                Capsule().fill(glow.opacity(0.9))
                    .frame(width: size * 0.035, height: size * 0.16)
            }
            .rotationEffect(.degrees(mood == .working ? 14 : 8), anchor: .bottom)
            .offset(y: -diameter * 0.58)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.82, blue: 0.48), glow,
                                              Color(red: 0.9, green: 0.45, blue: 0.08)],
                                     center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: diameter * 0.62))
                .frame(width: diameter, height: diameter)
                .shadow(color: glow.opacity(0.55), radius: size * 0.16)

            // Joues.
            HStack(spacing: size * 0.42) {
                Circle().fill(Color(red: 1, green: 0.45, blue: 0.4).opacity(0.45))
                Circle().fill(Color(red: 1, green: 0.45, blue: 0.4).opacity(0.45))
            }
            .frame(width: size * 0.6, height: size * 0.1)
            .offset(y: size * 0.14)

            MascotEyes(mood: mood, gaze: gaze, blink: blink, color: Color(red: 0.2, green: 0.1, blue: 0.0),
                       lidColor: glow, eyeSize: CGSize(width: size * 0.12, height: size * 0.22), spacing: size * 0.24)
                .offset(y: -size * 0.04)

            MascotMouth(mood: mood, color: Color(red: 0.2, green: 0.1, blue: 0.0), width: size * 0.14)
                .offset(y: size * 0.19)
        }
        .offset(y: mood == .happy ? -size * 0.06 : 0)
    }
}

// MARK: - Bloop

/// Goutte gélatineuse en dégradé rose-violet, grands yeux blancs aux pupilles mobiles.
private struct BloopBody: View {
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat

    var body: some View {
        let width = size * 1.2
        let height = size * 1.0
        let colors: [Color] = mood == .angry
            ? [Color(red: 1, green: 0.42, blue: 0.35), Color(red: 0.85, green: 0.15, blue: 0.3)]
            : [Color(red: 1, green: 0.42, blue: 0.62), Color(red: 0.56, green: 0.36, blue: 1)]
        ZStack {
            GumdropShape()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width, height: height)
                .shadow(color: colors[1].opacity(0.45), radius: size * 0.12)
                .overlay(alignment: .topLeading) {
                    // Reflet brillant.
                    Ellipse().fill(.white.opacity(0.35))
                        .frame(width: size * 0.22, height: size * 0.12)
                        .rotationEffect(.degrees(-25))
                        .offset(x: width * 0.2, y: height * 0.14)
                }

            HStack(spacing: size * 0.08) {
                BloopEye(mood: mood, gaze: gaze, blink: blink, size: size, isLeft: true)
                BloopEye(mood: mood, gaze: gaze, blink: blink, size: size, isLeft: false)
            }
            .offset(y: -size * 0.02)

            MascotMouth(mood: mood, color: Color(red: 0.25, green: 0.05, blue: 0.2), width: size * 0.14)
                .offset(y: size * 0.24)
        }
        .scaleEffect(x: mood == .happy ? 1.06 : 1, y: mood == .happy ? 0.95 : 1, anchor: .bottom)
    }
}

/// Œil de Bloop : blanc ovale, pupille noire qui suit le regard.
struct BloopEye: View {
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat
    let isLeft: Bool
    var sclera: Color = .white
    var pupil = Color(red: 0.12, green: 0.05, blue: 0.15)

    var body: some View {
        let eye = CGSize(width: size * 0.3, height: size * 0.34 * (mood == .waiting ? 1.1 : 1))
        if mood == .happy {
            HappyArc()
                .stroke(sclera, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .frame(width: eye.width * 0.8, height: eye.height * 0.35)
                .frame(width: eye.width, height: eye.height)
        } else {
            ZStack {
                Ellipse().fill(sclera)
                Circle().fill(pupil)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(x: gaze.width * eye.width * 0.2, y: gaze.height * eye.height * 0.18 + (mood == .working ? eye.height * 0.12 : 0))
            }
            .frame(width: eye.width, height: eye.height)
            // Paupière : le haut de l'œil se ferme (clignement, concentration, colère).
            .mask(alignment: .bottom) {
                Rectangle().frame(height: eye.height * (1 - lidCover))
            }
            .rotationEffect(.degrees(mood == .angry ? (isLeft ? 12 : -12) : 0))
        }
    }

    private var lidCover: CGFloat {
        let base: CGFloat = switch mood {
        case .working: 0.35
        case .angry: 0.4
        default: 0
        }
        return min(0.92, base + blink * (1 - base))
    }
}

/// Goutte arrondie : dôme en haut, base large et légèrement aplatie.
private struct GumdropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.72),
                      control1: CGPoint(x: rect.minX + w * 0.86, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.36))
        path.addCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.95),
                      control2: CGPoint(x: rect.minX + w * 0.78, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.72),
                      control1: CGPoint(x: rect.minX + w * 0.22, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.95))
        path.addCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.36),
                      control2: CGPoint(x: rect.minX + w * 0.14, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Éléments communs

/// Paire d'yeux en capsule : regard, clignement et expressions (concentré, surpris, content, fâché).
struct MascotEyes: View {
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let color: Color
    let lidColor: Color
    let eyeSize: CGSize
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            eye(isLeft: true)
            eye(isLeft: false)
        }
        .offset(x: gaze.width * spacing * 0.3, y: gaze.height * eyeSize.height * 0.25)
    }

    @ViewBuilder
    private func eye(isLeft: Bool) -> some View {
        if mood == .happy {
            HappyArc()
                .stroke(color, style: StrokeStyle(lineWidth: eyeSize.width * 0.55, lineCap: .round))
                .frame(width: eyeSize.width * 1.5, height: eyeSize.height * 0.4)
                .frame(width: eyeSize.width * 1.5, height: eyeSize.height)
        } else {
            let height = eyeSize.height * heightScale * (1 - blink * 0.88)
            Capsule()
                .fill(color)
                .frame(width: eyeSize.width * (mood == .waiting ? 1.15 : 1), height: height)
                .overlay(alignment: .top) {
                    if mood == .angry {
                        // Sourcil : le coin intérieur de l'œil est masqué en biais.
                        Rectangle().fill(lidColor)
                            .frame(width: eyeSize.width * 2.2, height: eyeSize.height * 0.5)
                            .rotationEffect(.degrees(isLeft ? 28 : -28))
                            .offset(y: -eyeSize.height * 0.22)
                    }
                }
                .clipShape(Rectangle())
                .frame(height: eyeSize.height, alignment: mood == .working ? .bottom : .center)
        }
    }

    private var heightScale: CGFloat {
        switch mood {
        case .working: 0.55
        case .waiting: 1.15
        default: 1
        }
    }
}

/// Bouche discrète : absente au repos, sourire, « o » de surprise ou moue fâchée.
struct MascotMouth: View {
    let mood: MascotMood
    let color: Color
    let width: CGFloat

    var body: some View {
        switch mood {
        case .idle, .working:
            EmptyView()
        case .happy:
            HappyArc().rotation(.degrees(180))
                .stroke(color, style: StrokeStyle(lineWidth: width * 0.22, lineCap: .round))
                .frame(width: width, height: width * 0.4)
        case .waiting:
            Ellipse().fill(color).frame(width: width * 0.45, height: width * 0.55)
        case .angry:
            HappyArc()
                .stroke(color, style: StrokeStyle(lineWidth: width * 0.22, lineCap: .round))
                .frame(width: width * 0.8, height: width * 0.3)
        }
    }
}

/// Arc en forme de « ^ » arrondi (yeux plissés de joie).
struct HappyArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return path
    }
}

/// Pastille d'état : points pendant le travail, « ! » en attente, étincelle de joie, vapeur de colère.
private struct MoodBadge: View {
    let mood: MascotMood
    let size: CGFloat

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .black))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .overlay(Circle().strokeBorder(.black, lineWidth: size * 0.1))
        }
    }

    private var symbol: String? {
        switch mood {
        case .idle: nil
        case .working: "ellipsis"
        case .waiting: "exclamationmark"
        case .happy: "checkmark"
        case .angry: "flame.fill"
        }
    }

    private var background: Color {
        switch mood {
        case .working: Color(red: 0.25, green: 0.55, blue: 1)
        case .waiting: StandBy.amber
        case .happy: Color(red: 0.2, green: 0.78, blue: 0.35)
        default: Color(red: 1, green: 0.3, blue: 0.25)
        }
    }

    private var foreground: Color { mood == .waiting ? StandBy.onAccent : .white }
}
