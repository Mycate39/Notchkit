import SwiftUI

/// Dix petits robots (troisième planche de propositions).
struct RobotMascotBody: View {
    let design: MascotDesign
    let mood: MascotMood
    let gaze: CGSize
    let blink: CGFloat
    let size: CGFloat

    private var angry: Bool { mood == .angry }
    private let red = Color(red: 1, green: 0.3, blue: 0.26)
    private let screen = Color(red: 0.05, green: 0.06, blue: 0.08)

    var body: some View {
        switch design {
        case .bolt: bolt
        case .cubo: cubo
        case .dome: dome
        case .wheelie: wheelie
        case .tin: tin
        case .visor: visor
        case .spark: spark
        case .mono: mono
        case .chip: chip
        default: hover
        }
    }

    // MARK: Éléments communs

    /// Yeux lumineux sur un écran sombre.
    private func screenEyes(_ color: Color, width: CGFloat = 0.11, height: CGFloat = 0.2, spacing: CGFloat = 0.24) -> some View {
        MascotEyes(mood: mood, gaze: gaze, blink: blink, color: angry ? red : color, lidColor: screen,
                   eyeSize: CGSize(width: size * width, height: size * height), spacing: size * spacing)
            .shadow(color: (angry ? red : color).opacity(0.8), radius: size * 0.05)
    }

    private func mouth(_ color: Color, width: CGFloat = 0.12) -> some View {
        MascotMouth(mood: mood, color: angry ? red : color, width: size * width)
    }

    /// Antenne : tige et perle (lumineuse si `glow`).
    private func antenna(_ color: Color, ball: Color, height: CGFloat = 0.2) -> some View {
        VStack(spacing: 0) {
            Circle().fill(ball).frame(width: size * 0.12, height: size * 0.12)
                .shadow(color: ball, radius: size * 0.06)
            Capsule().fill(color).frame(width: size * 0.04, height: size * height)
        }
    }

    private func metal(_ light: Color, _ dark: Color) -> LinearGradient {
        LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Robots

    /// Tête ronde chromée, écran noir, antenne bleue.
    private var bolt: some View {
        ZStack {
            antenna(Color(red: 0.6, green: 0.63, blue: 0.68), ball: Color(red: 0.35, green: 0.7, blue: 1))
                .offset(y: -size * 0.56)
            Circle().fill(metal(Color(red: 0.92, green: 0.94, blue: 0.97), Color(red: 0.55, green: 0.58, blue: 0.64)))
                .frame(width: size * 0.98)
            Capsule().fill(screen).frame(width: size * 0.72, height: size * 0.46)
            screenEyes(Color(red: 0.4, green: 0.8, blue: 1))
            mouth(Color(red: 0.4, green: 0.8, blue: 1)).offset(y: size * 0.16)
            // Oreilles : deux boulons.
            HStack(spacing: size * 0.96) {
                Circle().fill(Color(red: 0.5, green: 0.53, blue: 0.6)).frame(width: size * 0.12)
                Circle().fill(Color(red: 0.5, green: 0.53, blue: 0.6)).frame(width: size * 0.12)
            }
        }
    }

    /// Boîte orange à rivets, yeux carrés sur écran.
    private var cubo: some View {
        let orange = angry ? red : Color(red: 1, green: 0.58, blue: 0.2)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(metal(orange, orange.opacity(0.75)))
                .frame(width: size * 1.05, height: size * 0.95)
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).fill(screen)
                .frame(width: size * 0.76, height: size * 0.52).offset(y: -size * 0.06)
            // Rivets aux quatre coins.
            ForEach(0..<4, id: \.self) { index in
                Circle().fill(.white.opacity(0.5)).frame(width: size * 0.06)
                    .offset(x: (index % 2 == 0 ? -1 : 1) * size * 0.42, y: (index < 2 ? -1 : 1) * size * 0.37)
            }
            screenEyes(Color(red: 1, green: 0.85, blue: 0.4), width: 0.13, height: 0.17).offset(y: -size * 0.06)
            mouth(Color(red: 0.25, green: 0.1, blue: 0)).offset(y: size * 0.32)
        }
    }

    /// Dôme de verre sur un socle chromé, visage lumineux à l'intérieur.
    private var dome: some View {
        ZStack {
            Capsule().fill(metal(Color(red: 0.85, green: 0.87, blue: 0.9), Color(red: 0.45, green: 0.48, blue: 0.55)))
                .frame(width: size * 1.05, height: size * 0.3).offset(y: size * 0.36)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.45), screen],
                                     center: .center, startRadius: 0, endRadius: size * 0.45))
                .frame(width: size * 0.86)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: max(1, size * 0.025)))
                .overlay(alignment: .topLeading) {
                    Capsule().fill(.white.opacity(0.4)).frame(width: size * 0.18, height: size * 0.06)
                        .rotationEffect(.degrees(-35)).offset(x: size * 0.16, y: size * 0.18)
                }
                .offset(y: -size * 0.06)
            screenEyes(Color(red: 0.75, green: 0.55, blue: 1)).offset(y: -size * 0.08)
            mouth(Color(red: 0.75, green: 0.55, blue: 1)).offset(y: size * 0.1)
        }
    }

    /// Corps en capsule debout sur une roue.
    private var wheelie: some View {
        let teal = angry ? red : Color(red: 0.2, green: 0.8, blue: 0.75)
        return ZStack {
            Circle().fill(Color(red: 0.18, green: 0.18, blue: 0.2))
                .overlay(Circle().fill(Color(red: 0.5, green: 0.52, blue: 0.56)).padding(size * 0.07))
                .frame(width: size * 0.32).offset(y: size * 0.46)
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(metal(teal, teal.opacity(0.7)))
                .frame(width: size * 0.78, height: size * 0.82)
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).fill(screen)
                .frame(width: size * 0.56, height: size * 0.36).offset(y: -size * 0.1)
            screenEyes(.white, width: 0.1, height: 0.16, spacing: 0.18).offset(y: -size * 0.1)
            mouth(Color(red: 0.05, green: 0.25, blue: 0.22)).offset(y: size * 0.2)
        }
    }

    /// Robot jouet en fer-blanc : tête rouge, boulons d'oreilles, grille en bouche.
    private var tin: some View {
        let body = angry ? Color(red: 0.75, green: 0.1, blue: 0.1) : Color(red: 0.88, green: 0.25, blue: 0.22)
        return ZStack {
            antenna(Color(red: 0.7, green: 0.7, blue: 0.72), ball: Color(red: 1, green: 0.85, blue: 0.3), height: 0.14)
                .offset(y: -size * 0.53)
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(metal(body, body.opacity(0.8)))
                .frame(width: size * 0.98, height: size * 0.82)
            HStack(spacing: size * 0.98) {
                RoundedRectangle(cornerRadius: size * 0.03).fill(Color(red: 0.7, green: 0.7, blue: 0.72))
                    .frame(width: size * 0.1, height: size * 0.3)
                RoundedRectangle(cornerRadius: size * 0.03).fill(Color(red: 0.7, green: 0.7, blue: 0.72))
                    .frame(width: size * 0.1, height: size * 0.3)
            }
            // Yeux ronds blancs à pupilles.
            HStack(spacing: size * 0.08) {
                BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 0.7, isLeft: true,
                         sclera: Color(red: 1, green: 0.97, blue: 0.88), pupil: .black)
                BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 0.7, isLeft: false,
                         sclera: Color(red: 1, green: 0.97, blue: 0.88), pupil: .black)
            }
            .offset(y: -size * 0.1)
            // Grille.
            if mood == .idle || mood == .working {
                HStack(spacing: size * 0.04) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Color(red: 0.35, green: 0.08, blue: 0.08)).frame(width: size * 0.04, height: size * 0.12)
                    }
                }
                .offset(y: size * 0.24)
            } else {
                mouth(Color(red: 0.35, green: 0.08, blue: 0.08), width: 0.16).offset(y: size * 0.24)
            }
        }
    }

    /// Casque menthe et bandeau noir où les yeux brillent.
    private var visor: some View {
        let shell = angry ? Color(red: 1, green: 0.6, blue: 0.55) : Color(red: 0.8, green: 0.98, blue: 0.9)
        return ZStack {
            Ellipse().fill(metal(.white, shell))
                .frame(width: size * 1.05, height: size * 0.92)
            Capsule().fill(screen).frame(width: size * 0.86, height: size * 0.32).offset(y: -size * 0.04)
            screenEyes(Color(red: 0.3, green: 1, blue: 0.8), width: 0.12, height: 0.15, spacing: 0.26).offset(y: -size * 0.04)
            mouth(Color(red: 0.2, green: 0.4, blue: 0.35)).offset(y: size * 0.24)
        }
    }

    /// Tête ronde surmontée d'une ampoule qui s'allume selon l'humeur.
    private var spark: some View {
        let bulb: Color = switch mood {
        case .happy: Color(red: 0.4, green: 1, blue: 0.5)
        case .waiting: StandBy.amber
        case .angry: red
        default: Color(red: 1, green: 0.95, blue: 0.6)
        }
        return ZStack {
            VStack(spacing: 0) {
                Circle().fill(bulb).frame(width: size * 0.24).shadow(color: bulb, radius: size * 0.12)
                RoundedRectangle(cornerRadius: size * 0.02).fill(Color(red: 0.6, green: 0.6, blue: 0.62))
                    .frame(width: size * 0.13, height: size * 0.1)
            }
            .offset(y: -size * 0.56)
            RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
                .fill(metal(Color(red: 0.42, green: 0.45, blue: 0.95), Color(red: 0.25, green: 0.25, blue: 0.7)))
                .frame(width: size * 1.0, height: size * 0.84)
            Capsule().fill(screen).frame(width: size * 0.7, height: size * 0.4).offset(y: -size * 0.04)
            screenEyes(.white).offset(y: -size * 0.04)
            mouth(.white).offset(y: size * 0.26)
        }
    }

    /// Cyclope jaune : un seul grand œil d'objectif.
    private var mono: some View {
        let yellow = angry ? red : Color(red: 1, green: 0.82, blue: 0.2)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(metal(yellow, yellow.opacity(0.75)))
                .frame(width: size * 0.95, height: size * 0.92)
            Circle().fill(Color(red: 0.15, green: 0.15, blue: 0.18)).frame(width: size * 0.56)
                .offset(y: -size * 0.06)
            BloopEye(mood: mood, gaze: gaze, blink: blink, size: size * 1.3, isLeft: true,
                     sclera: Color(red: 0.92, green: 0.96, blue: 1), pupil: Color(red: 0.1, green: 0.35, blue: 0.75))
                .scaleEffect(0.9)
                .offset(y: -size * 0.06)
            mouth(Color(red: 0.3, green: 0.2, blue: 0)).offset(y: size * 0.32)
        }
    }

    /// Puce électronique verte avec ses pattes, LED en guise d'yeux.
    private var chip: some View {
        let board = angry ? Color(red: 0.55, green: 0.12, blue: 0.1) : Color(red: 0.1, green: 0.4, blue: 0.25)
        return ZStack {
            // Pattes de chaque côté.
            HStack(spacing: size * 0.86) {
                VStack(spacing: size * 0.08) { ForEach(0..<4, id: \.self) { _ in pin } }
                VStack(spacing: size * 0.08) { ForEach(0..<4, id: \.self) { _ in pin } }
            }
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(metal(board.opacity(0.9), board))
                .frame(width: size * 0.92, height: size * 0.88)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .strokeBorder(Color(red: 0.85, green: 0.75, blue: 0.4).opacity(0.6), lineWidth: max(1, size * 0.02))
                        .padding(size * 0.07)
                }
            screenEyes(Color(red: 0.5, green: 1, blue: 0.4), width: 0.12, height: 0.12)
                .offset(y: -size * 0.06)
            mouth(Color(red: 0.85, green: 0.75, blue: 0.4)).offset(y: size * 0.18)
        }
    }

    private var pin: some View {
        Capsule().fill(Color(red: 0.8, green: 0.8, blue: 0.82)).frame(width: size * 0.16, height: size * 0.06)
    }

    /// Petit drone qui flotte : hélice sur la tête, ombre au sol.
    private var hover: some View {
        let shell = angry ? red : Color(red: 0.72, green: 0.65, blue: 1)
        return ZStack {
            Ellipse().fill(.black.opacity(0.0)).frame(width: 1, height: 1)
            Ellipse().fill(shell.opacity(0.25)).frame(width: size * 0.6, height: size * 0.1)
                .blur(radius: size * 0.03).offset(y: size * 0.56)
            VStack(spacing: 0) {
                Capsule().fill(Color(red: 0.8, green: 0.8, blue: 0.85)).frame(width: size * 0.6, height: size * 0.05)
                Capsule().fill(Color(red: 0.6, green: 0.6, blue: 0.66)).frame(width: size * 0.05, height: size * 0.1)
            }
            .offset(y: -size * 0.5)
            Ellipse().fill(metal(.white, shell))
                .frame(width: size * 1.05, height: size * 0.78)
            Capsule().fill(screen).frame(width: size * 0.66, height: size * 0.36).offset(y: -size * 0.02)
            screenEyes(Color(red: 0.95, green: 0.8, blue: 1)).offset(y: -size * 0.02)
            mouth(Color(red: 0.3, green: 0.2, blue: 0.5)).offset(y: size * 0.24)
        }
        .offset(y: -size * 0.04)
    }
}
