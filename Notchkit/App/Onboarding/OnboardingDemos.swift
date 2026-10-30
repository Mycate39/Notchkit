import SwiftUI

// Petites démonstrations animées du tutoriel : un bout d'écran (fond, barre des menus) et la forme de
// l'encoche, avec le fond choisi (noir ou verre), qui rejouent en boucle ce que fait Notchkit.

/// Dimensions communes des démonstrations.
enum OnboardingDemoLayout {
    static let size = CGSize(width: 420, height: 160)
    static let menuBarHeight: CGFloat = 14
    /// Encoche au repos, activité compacte, lecteur de musique, pages de widgets étroite et large.
    static let idle = CGSize(width: 74, height: 14)
    static let compact = CGSize(width: 100, height: 14)
    static let player = CGSize(width: 232, height: 94)
    static let narrowPage = CGSize(width: 196, height: 100)
    static let widePage = CGSize(width: 312, height: 100)
    /// Bulle à droite de l'encoche, au repos puis allongée avec ses commandes.
    static let bubble = CGSize(width: 22, height: 14)
    static let bubbleWithControls = CGSize(width: 74, height: 14)
    static let bubbleSpacing: CGFloat = 5
    /// Grossissement des démonstrations de l'encoche repliée (activité, bulles), trop petites sinon.
    static let compactZoom: CGFloat = 1.8
    /// Grossissement de la démonstration des bulles : l'encoche et ses deux bulles doivent tenir.
    static let bubblesZoom: CGFloat = 1.28
}

extension EnvironmentValues {
    /// Apparence de l'encoche réelle, reprise par les démonstrations (fond noir ou verre).
    @Entry var onboardingAppearance = NotchAppearance()
}

/// Bout d'écran : fond dégradé et barre des menus schématique. `zoom` grossit le haut de l'écran
/// (barre des menus et encoche) autour de l'encoche, comme une loupe.
struct DemoScreen<Content: View>: View {
    var zoom: CGFloat = 1
    /// Menus à gauche et icônes à droite de la barre des menus : moins nombreux dans une vue grossie,
    /// pour qu'ils ne passent pas sous l'encoche ni entre ses bulles.
    var menus = 4
    var extras = 3
    @ViewBuilder var content: Content

    var body: some View {
        let size = OnboardingDemoLayout.size
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.62), Color(red: 0.52, green: 0.3, blue: 0.78),
                                    Color(red: 0.93, green: 0.55, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack(alignment: .top) {
                HStack(spacing: 9) {
                    ForEach(0..<menus, id: \.self) { _ in
                        Capsule().fill(.white.opacity(0.55)).frame(width: 20, height: 4)
                    }
                    Spacer()
                    ForEach(0..<extras, id: \.self) { _ in
                        Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: OnboardingDemoLayout.menuBarHeight)
                .background(.black.opacity(0.18))
                content
            }
            .frame(width: size.width / zoom, height: size.height / zoom, alignment: .top)
            .scaleEffect(zoom, anchor: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Encoche schématique collée au haut de l'écran : petits coins repliée, oreilles et grands coins
/// ouverte, comme l'encoche réelle ; fond noir, ou verre sous la découpe une fois ouverte.
struct DemoNotch<Content: View>: View {
    var size: CGSize
    var isExpanded = false
    /// Contour de l'activité (couleur de la musique, ambre d'une demande), comme les Live Activities.
    var keyLine: Color?
    @ViewBuilder var content: Content
    @Environment(\.onboardingAppearance) private var appearance

    var body: some View {
        let shape = NotchShape(earRadius: isExpanded ? 7 : 4, topCornerRadius: 0, bottomCornerRadius: isExpanded ? 18 : 6)
        content
            .frame(width: size.width, height: size.height)
            .background { background }
            .clipShape(shape)
            // Contour sur les côtés et le bas seulement : le haut touche le bord de l'écran.
            .overlay {
                shape.stroke((keyLine ?? .clear).opacity(0.8), lineWidth: 1)
                    .mask(Rectangle().padding(.top, 1.5))
            }
    }

    /// Fond noir, ou verre dessiné (flou, noir sous la découpe puis dégradé) : le Liquid Glass de
    /// l'encoche ne suivait pas la taille animée des démonstrations et restait décalé.
    @ViewBuilder
    private var background: some View {
        if appearance.usesGlassWidgets {
            GeometryReader { proxy in
                let fadeStart = min(1, max(OnboardingDemoLayout.menuBarHeight / max(proxy.size.height, 1),
                                           NotchLayout.glassBlackFraction))
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    Color.black.opacity(NotchLayout.glassTint)
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: fadeStart),
                        .init(color: .black.opacity(NotchLayout.glassBottomDarkness), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    // Repliée, l'encoche reste entièrement noire.
                    Color.black.opacity(isExpanded ? 0 : 1)
                }
            }
        } else {
            Color.black
        }
    }
}

/// Pointeur de la souris, avec son ombre.
private struct DemoPointer: View {
    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(radius: 2)
    }
}

/// Pochette du morceau.
private struct DemoArtwork: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }
}

/// Barres de son animées.
private struct DemoBars: View {
    var body: some View {
        PhaseAnimator([0.4, 1.0, 0.6]) { level in
            HStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(.pink.opacity(0.9))
                        .frame(width: 2, height: 3 + 6 * (index == 1 ? level : 1.2 - level))
                }
            }
            .frame(height: 10)
        } animation: { _ in .easeInOut(duration: 0.35) }
    }
}

/// Activité musique de l'encoche repliée : pochette à gauche, barres à droite.
private struct DemoMusicActivity: View {
    var body: some View {
        HStack {
            DemoArtwork(size: 10)
            Spacer(minLength: 0)
            DemoBars()
        }
        .padding(.horizontal, 8)
    }
}

/// Petit lecteur façon iPhone, première page de l'encoche ouverte : pochette et titre, barre de
/// lecture, puis aléatoire, précédent, pause, suivant et répétition.
private struct DemoPlayer: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                DemoArtwork(size: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(.white.opacity(0.9)).frame(width: 74, height: 5)
                    Capsule().fill(.white.opacity(0.45)).frame(width: 48, height: 4)
                }
                Spacer(minLength: 0)
                DemoBars()
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white.opacity(0.85)).frame(width: 70)
            }
            .frame(height: 3)
            HStack {
                Image(systemName: "shuffle").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Image(systemName: "backward.fill")
                Spacer()
                Image(systemName: "pause.fill").font(.system(size: 13, weight: .bold))
                Spacer()
                Image(systemName: "forward.fill")
                Spacer()
                Image(systemName: "repeat").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
        // Largeur de l'encoche ouverte sur le lecteur : sans elle, il prenait celle de la rangée de
        // widgets superposée et sortait de l'encoche des deux côtés.
        .frame(width: OnboardingDemoLayout.player.width)
    }
}

/// Widget posé sur l'encoche : sur une carte avec le fond noir, directement sur le verre sinon.
private struct DemoWidget: View {
    let symbol: String
    let tint: Color
    var width: CGFloat = 62
    @Environment(\.onboardingAppearance) private var appearance

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(appearance.usesGlassWidgets ? Color.clear : .white.opacity(0.1))
            .frame(width: width, height: 54)
            .overlay(Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint))
    }
}

/// Rangée de widgets d'une page.
private struct DemoWidgetRow: View {
    let widgets: [(String, Color)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(widgets.indices, id: \.self) { index in
                DemoWidget(symbol: widgets[index].0, tint: widgets[index].1)
            }
        }
        .padding(.top, 24)
    }
}

/// Bouton rond d'une bulle (pause, arrêt, autoriser, refuser), aux couleurs des vrais.
private struct DemoBubbleButton: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .heavy))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.22), in: Circle())
    }
}

// MARK: - Démonstrations par étape

/// Bienvenue : l'encoche au repos, puis la musique qui s'y installe.
struct WelcomeDemo: View {
    var body: some View {
        DemoScreen(zoom: OnboardingDemoLayout.compactZoom, menus: 2, extras: 2) {
            PhaseAnimator([false, true]) { active in
                DemoNotch(size: active ? OnboardingDemoLayout.compact : OnboardingDemoLayout.idle,
                          keyLine: active ? .pink : nil) {
                    DemoMusicActivity().opacity(active ? 1 : 0)
                }
            } animation: { _ in .spring(duration: 0.6, bounce: 0.25).delay(1.2) }
        }
    }
}

/// Survol : le pointeur s'approche, l'encoche s'ouvre sur le lecteur de musique, un balayage passe aux
/// widgets (l'encoche prend leur largeur), puis elle se referme quand le pointeur s'éloigne.
struct HoverDemo: View {
    private enum Phase: CaseIterable { case away, over, player, widgets, leave }

    var body: some View {
        DemoScreen {
            PhaseAnimator(Phase.allCases) { phase in
                ZStack(alignment: .top) {
                    DemoNotch(size: size(phase), isExpanded: phase == .player || phase == .widgets) {
                        // Les pages glissent comme dans l'encoche : le lecteur part à gauche, les widgets
                        // arrivent par la droite. Hors balayage, les pages se replacent sans être vues.
                        let swiped = phase == .widgets || phase == .leave
                        let pageWidth = OnboardingDemoLayout.widePage.width
                        ZStack(alignment: .top) {
                            DemoPlayer()
                                .offset(x: swiped ? -pageWidth : 0)
                                .opacity(phase == .player || phase == .widgets ? 1 : 0)
                            DemoWidgetRow(widgets: [("clock.fill", .white), ("battery.75percent", .green),
                                                    ("cloud.sun.fill", .yellow), ("calendar", .red)])
                                .frame(width: pageWidth)
                                .offset(x: swiped ? 0 : pageWidth)
                                .opacity(phase == .widgets ? 1 : 0)
                        }
                    }
                    DemoPointer().offset(pointerOffset(phase))
                    // Balayage à deux doigts : deux points qui glissent vers la gauche.
                    HStack(spacing: 4) {
                        Circle().frame(width: 7, height: 7)
                        Circle().frame(width: 7, height: 7)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(x: phase == .widgets ? -34 : 20, y: 118)
                    .opacity(phase == .widgets ? 1 : 0)
                }
            } animation: { phase in
                switch phase {
                case .away: .easeInOut(duration: 0.7).delay(0.8)
                case .over: .easeInOut(duration: 0.7)
                case .player: .spring(duration: 0.5, bounce: 0.2).delay(0.15)
                case .widgets: .spring(duration: 0.55, bounce: 0.15).delay(1.8)
                case .leave: .easeInOut(duration: 0.7).delay(1.8)
                }
            }
        }
    }

    private func size(_ phase: Phase) -> CGSize {
        switch phase {
        case .player: OnboardingDemoLayout.player
        case .widgets: OnboardingDemoLayout.widePage
        default: OnboardingDemoLayout.idle
        }
    }

    private func pointerOffset(_ phase: Phase) -> CGSize {
        switch phase {
        case .away: CGSize(width: 120, height: 112)
        case .over, .player, .widgets: CGSize(width: 6, height: 6)
        case .leave: CGSize(width: 140, height: 120)
        }
    }
}

/// Activités : la musique s'installe autour de l'encoche, un minuteur et Claude Code deviennent des
/// bulles ; survolée, la bulle du minuteur montre le temps restant et ses commandes, celle de l'agent
/// (cerclée d'ambre : il attend une réponse) propose Autoriser et Refuser.
struct ActivitiesDemo: View {
    let mascot: MascotDesign
    private enum Phase: CaseIterable { case idle, music, bubbles, timer, agent }

    var body: some View {
        DemoScreen(zoom: OnboardingDemoLayout.bubblesZoom, menus: 3, extras: 0) {
            PhaseAnimator(Phase.allCases) { phase in
                let active = phase != .idle
                DemoNotch(size: active ? OnboardingDemoLayout.compact : OnboardingDemoLayout.idle,
                          keyLine: active ? .pink : nil) {
                    DemoMusicActivity().opacity(active ? 1 : 0)
                }
                // Bulles accrochées à droite de l'encoche, qui reste ainsi centrée.
                .overlay(alignment: .topTrailing) {
                    bubbles(phase).alignmentGuide(.trailing) { $0[.leading] - OnboardingDemoLayout.bubbleSpacing }
                }
            } animation: { phase in
                switch phase {
                case .idle: .spring(duration: 0.6, bounce: 0.25).delay(0.6)
                case .music, .bubbles: .spring(duration: 0.6, bounce: 0.25).delay(1.3)
                case .timer, .agent: .spring(duration: 0.5, bounce: 0.2).delay(1.4)
                }
            }
        }
    }

    private func bubbles(_ phase: Phase) -> some View {
        let visible = phase == .bubbles || phase == .timer || phase == .agent
        return HStack(alignment: .top, spacing: OnboardingDemoLayout.bubbleSpacing) {
            DemoNotch(size: phase == .timer ? OnboardingDemoLayout.bubbleWithControls : OnboardingDemoLayout.bubble,
                      keyLine: .orange) {
                HStack(spacing: 4) {
                    Image(systemName: "timer").foregroundStyle(.orange)
                    if phase == .timer {
                        Text(verbatim: "4:12").foregroundStyle(.orange).fixedSize()
                        DemoBubbleButton(symbol: "pause.fill", tint: .orange)
                        DemoBubbleButton(symbol: "xmark", tint: .white)
                    }
                }
                .font(.system(size: 8, weight: .bold).monospacedDigit())
                .padding(.horizontal, 4)
            }
            DemoNotch(size: phase == .agent ? OnboardingDemoLayout.bubbleWithControls : OnboardingDemoLayout.bubble,
                      keyLine: StandBy.amber) {
                HStack(spacing: 5) {
                    MascotView(design: mascot, mood: .waiting, size: 11, showsBadge: false)
                    if phase == .agent {
                        DemoBubbleButton(symbol: "checkmark", tint: .green)
                        DemoBubbleButton(symbol: "xmark", tint: .white)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            DemoPointer()
                .offset(pointerOffset(phase))
                .opacity(phase == .timer || phase == .agent ? 1 : 0)
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.4, anchor: .topLeading)
    }

    private func pointerOffset(_ phase: Phase) -> CGSize {
        switch phase {
        case .timer: CGSize(width: 30, height: 7)
        case .agent: CGSize(width: OnboardingDemoLayout.bubble.width + OnboardingDemoLayout.bubbleSpacing + 34, height: 7)
        default: CGSize(width: 60, height: 100)
        }
    }
}

/// Fichiers : un document glisse vers l'encoche, qui s'ouvre sur l'étagère, la conversion et AirDrop ;
/// déposé sur l'étagère, il y reste et l'étagère devient une activité.
/// Animation par images clés (une seule horloge pour le document et l'encoche) : les phases
/// enchaînées de `PhaseAnimator` se décalaient et le document traversait l'écran à l'envers.
struct FilesDemo: View {
    /// Instants clés de la boucle (secondes).
    private enum Time {
        static let rest = 1.0          // document au repos
        static let reach = 2.0         // document arrivé sous l'encoche, qui s'ouvre
        static let hover = 2.5         // document au-dessus de l'étagère
        static let drop = 3.4          // lâché : l'encoche se referme sur l'étagère
        static let kept = 5.4          // l'étagère disparaît, l'encoche revient au repos
        static let loop = 6.2          // fin de la boucle
    }

    var body: some View {
        DemoScreen {
            TimelineView(.animation(paused: NotchAccessibility.reduceMotion)) { context in
                let t = NotchAccessibility.reduceMotion ? Time.hover
                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Time.loop)
                frame(at: t)
            }
        }
    }

    private func frame(at t: Double) -> some View {
        let open = t >= Time.reach && t < Time.drop
        // Ouverture et fermeture de l'encoche sur 0,3 s.
        let opening = smooth((t - Time.reach) / 0.3)
        let closing = smooth((t - Time.drop) / 0.3)
        let openAmount = open ? opening : (t >= Time.drop ? 1 - closing : 0)
        // Après le dépôt, l'encoche se referme sur l'étagère, puis revient au repos avant la boucle suivante.
        let shelfAmount = t >= Time.drop ? 1 - smooth((t - Time.kept) / 0.4) : 0
        let closedWidth = OnboardingDemoLayout.idle.width
            + (OnboardingDemoLayout.compact.width - OnboardingDemoLayout.idle.width) * shelfAmount
        let size = CGSize(
            width: closedWidth + (OnboardingDemoLayout.widePage.width - closedWidth) * openAmount,
            height: OnboardingDemoLayout.idle.height + (OnboardingDemoLayout.widePage.height - OnboardingDemoLayout.idle.height) * openAmount
        )
        return ZStack(alignment: .top) {
            DemoNotch(size: size, isExpanded: openAmount > 0.5) {
                ZStack(alignment: .top) {
                    HStack(spacing: 8) {
                        zone("tray.and.arrow.down.fill", color: .green, highlighted: t >= Time.hover)
                        zone("arrow.triangle.2.circlepath", color: .orange, highlighted: false)
                        zone("dot.radiowaves.left.and.right", color: .blue, highlighted: false)
                    }
                    .padding(.top, 24)
                    .frame(width: OnboardingDemoLayout.widePage.width)
                    .opacity(open ? openAmount : 0)
                    // Fichier gardé : l'étagère devient une activité, son nombre de fichiers à droite.
                    HStack {
                        Image(systemName: "tray.full.fill").foregroundStyle(.white.opacity(0.85))
                        Spacer(minLength: 0)
                        Text(verbatim: "1").foregroundStyle(.green)
                    }
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 9)
                    .frame(width: OnboardingDemoLayout.compact.width, height: OnboardingDemoLayout.idle.height)
                    .opacity(t >= Time.drop ? min(closing, shelfAmount) : 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            Image(systemName: "doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .offset(documentOffset(at: t))
                .opacity(documentOpacity(at: t))
        }
    }

    /// Trajet du document : départ en bas à gauche, sous l'encoche, puis au-dessus de l'étagère.
    private func documentOffset(at t: Double) -> CGSize {
        let start = CGSize(width: -150, height: 106)
        let reach = CGSize(width: -30, height: 20)
        let shelf = CGSize(width: -96, height: 48)
        if t < Time.rest { return start }
        if t < Time.reach { return mix(start, reach, smooth((t - Time.rest) / (Time.reach - Time.rest))) }
        if t < Time.hover { return mix(reach, shelf, smooth((t - Time.reach) / (Time.hover - Time.reach))) }
        return shelf
    }

    /// Le document disparaît au dépôt et revient à son départ en fondu, à la fin de la boucle.
    private func documentOpacity(at t: Double) -> Double {
        if t >= Time.drop { return max(0, 1 - (t - Time.drop) / 0.2) }
        if t < 0.4 { return t / 0.4 }
        return 1
    }

    private func smooth(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func mix(_ a: CGSize, _ b: CGSize, _ f: Double) -> CGSize {
        CGSize(width: a.width + (b.width - a.width) * f, height: a.height + (b.height - a.height) * f)
    }

    private func zone(_ symbol: String, color: Color, highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(highlighted ? color.opacity(0.3) : .white.opacity(0.08))
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(highlighted ? color : .white.opacity(0.3))
            .frame(width: 88, height: 58)
            .overlay(Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(highlighted ? color : .white.opacity(0.8)))
    }
}

/// Agents : la mascotte travaille, puis Claude Code demande une autorisation (Autoriser en vert,
/// Refuser en blanc, comme dans l'encoche), et la tâche se termine.
struct AgentsDemo: View {
    let mascot: MascotDesign
    private enum Phase: CaseIterable { case working, asking, answered }

    var body: some View {
        DemoScreen {
            PhaseAnimator(Phase.allCases) { phase in
                DemoNotch(size: OnboardingDemoLayout.widePage, isExpanded: true) {
                    HStack(spacing: 14) {
                        MascotView(design: mascot, mood: mood(phase), size: 44, showsBadge: false)
                            .frame(width: 60)
                        // Étapes de l'agent ; la dernière devient la demande d'autorisation, puis se coche.
                        VStack(alignment: .leading, spacing: 7) {
                            step(done: true, width: 80)
                            step(done: true, width: 64)
                            ZStack(alignment: .leading) {
                                step(done: phase == .answered, width: 48)
                                    .opacity(phase == .asking ? 0 : 1)
                                HStack(spacing: 6) {
                                    Text(verbatim: "npm test")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(StandBy.amber)
                                    DemoBubbleButton(symbol: "checkmark", tint: .green, size: 16)
                                    DemoBubbleButton(symbol: "xmark", tint: .white, size: 16)
                                }
                                .opacity(phase == .asking ? 1 : 0)
                            }
                            .frame(height: 16)
                        }
                        .frame(width: 150, alignment: .leading)
                    }
                    .padding(.top, 22)
                }
            } animation: { _ in .spring(duration: 0.5, bounce: 0.2).delay(1.6) }
        }
    }

    private func step(done: Bool, width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(done ? .green : .white.opacity(0.6))
            Capsule().fill(.white.opacity(0.35)).frame(width: width, height: 4)
        }
        .font(.system(size: 9))
    }

    private func mood(_ phase: Phase) -> MascotMood {
        switch phase {
        case .working: .working
        case .asking: .waiting
        case .answered: .happy
        }
    }
}

/// Widgets : l'encoche passe d'une page à l'autre et prend chaque fois la largeur de ses widgets.
struct WidgetsDemo: View {
    var body: some View {
        DemoScreen {
            PhaseAnimator([false, true]) { wide in
                DemoNotch(size: wide ? OnboardingDemoLayout.widePage : OnboardingDemoLayout.narrowPage, isExpanded: true) {
                    // Changement de page : la page courante glisse d'un côté, la suivante arrive de l'autre.
                    let shift = OnboardingDemoLayout.widePage.width
                    ZStack(alignment: .top) {
                        DemoWidgetRow(widgets: [("clock.fill", .white), ("battery.75percent", .green)])
                            .frame(width: OnboardingDemoLayout.narrowPage.width)
                            .offset(x: wide ? -shift : 0)
                            .opacity(wide ? 0 : 1)
                        DemoWidgetRow(widgets: [("calendar", .red), ("cloud.sun.fill", .yellow),
                                                ("timer", .orange), ("doc.on.clipboard", .teal)])
                            .frame(width: OnboardingDemoLayout.widePage.width)
                            .offset(x: wide ? 0 : shift)
                            .opacity(wide ? 1 : 0)
                    }
                }
            } animation: { _ in .spring(duration: 0.55, bounce: 0.15).delay(1.6) }
        }
    }
}

/// Essai : flèche qui montre la vraie encoche, en haut de l'écran.
struct TryItDemo: View {
    var body: some View {
        DemoScreen {
            VStack(spacing: 12) {
                DemoNotch(size: OnboardingDemoLayout.idle) { Color.clear }
                PhaseAnimator([false, true]) { up in
                    Image(systemName: "arrow.up")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(y: up ? -6 : 6)
                } animation: { _ in .easeInOut(duration: 0.7) }
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Fin : la mascotte, contente, dans l'encoche ; l'icône de Notchkit dans la barre des menus, où l'on
/// retrouve les réglages et ce tutoriel, s'allume.
struct DoneDemo: View {
    let mascot: MascotDesign

    var body: some View {
        DemoScreen(zoom: Self.zoom, menus: 3, extras: 2) {
            DemoNotch(size: CGSize(width: 96, height: OnboardingDemoLayout.idle.height), keyLine: .green) {
                HStack {
                    MascotView(design: mascot, mood: .happy, size: 11, showsBadge: false)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
            }
            // Icône de Notchkit, avant les autres icônes de la barre des menus.
            PhaseAnimator([false, true]) { lit in
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 12)
                    .background(.white.opacity(lit ? 0.35 : 0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            } animation: { _ in .easeInOut(duration: 0.8) }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 50)
            .frame(height: OnboardingDemoLayout.menuBarHeight)
        }
    }

    /// Un peu moins que les autres : l'icône de la barre des menus doit rester visible.
    private static let zoom: CGFloat = 1.5
}

/// Synthèse des autorisations : chacune avec son état en direct, sur l'écran de démonstration.
struct PermissionsDemo: View {
    let center: PermissionCenter

    var body: some View {
        DemoScreen {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 5) {
                ForEach(AppPermission.allCases) { permission in
                    let state = center.state(of: permission)
                    HStack(spacing: 6) {
                        PermissionIcon(permission: permission, size: 18)
                        Text(permission.shortTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Circle()
                            .fill(state == .granted ? Color.green : state == .denied ? Color.red : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, OnboardingDemoLayout.menuBarHeight + 8)
        }
    }
}
