import SwiftUI

// Petites démonstrations animées du tutoriel : un bout d'écran (fond, barre des menus) et la vraie
// forme de l'encoche, qui rejouent en boucle ce que fait Notchkit.

/// Dimensions communes des démonstrations.
enum OnboardingDemoLayout {
    static let size = CGSize(width: 380, height: 150)
    static let menuBarHeight: CGFloat = 14
    /// Encoche au repos, activité compacte, encoche dépliée.
    static let idle = CGSize(width: 74, height: 14)
    static let compact = CGSize(width: 128, height: 14)
    static let expanded = CGSize(width: 262, height: 96)
}

/// Bout d'écran : fond dégradé et barre des menus schématique.
struct DemoScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.24, green: 0.2, blue: 0.7), Color(red: 0.55, green: 0.32, blue: 0.82)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 9) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.55)).frame(width: 20, height: 4)
                }
                Spacer()
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: OnboardingDemoLayout.menuBarHeight)
            .background(.black.opacity(0.18))
            content
        }
        .frame(width: OnboardingDemoLayout.size.width, height: OnboardingDemoLayout.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Encoche schématique : forme noire collée au haut de l'écran, contenu découpé à sa forme.
struct DemoNotch<Content: View>: View {
    var size: CGSize
    var isExpanded = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = NotchShape(earRadius: 4, topCornerRadius: isExpanded ? 10 : 4, bottomCornerRadius: isExpanded ? 18 : 6)
        content
            .frame(width: size.width, height: size.height)
            .background(.black)
            .clipShape(shape)
    }
}

/// Pochette et barres animées de l'activité musique.
private struct DemoMusicActivity: View {
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 10, height: 10)
            Spacer(minLength: 0)
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
        .padding(.horizontal, 8)
    }
}

// MARK: - Démonstrations par étape

/// Bienvenue : l'encoche au repos, puis une activité qui s'y installe.
struct WelcomeDemo: View {
    var body: some View {
        DemoScreen {
            PhaseAnimator([false, true]) { active in
                DemoNotch(size: active ? OnboardingDemoLayout.compact : OnboardingDemoLayout.idle) {
                    DemoMusicActivity().opacity(active ? 1 : 0)
                }
            } animation: { _ in .spring(duration: 0.6, bounce: 0.25).delay(1.2) }
        }
    }
}

/// Survol : le pointeur s'approche, l'encoche se déplie sur des cartes, puis se referme.
struct HoverDemo: View {
    private enum Phase: CaseIterable { case away, over, open, leave }

    var body: some View {
        DemoScreen {
            PhaseAnimator(Phase.allCases) { phase in
                let isOpen = phase == .open
                ZStack(alignment: .top) {
                    DemoNotch(size: isOpen ? OnboardingDemoLayout.expanded : OnboardingDemoLayout.idle, isExpanded: isOpen) {
                        HStack(spacing: 8) {
                            card("music.note", tint: .pink)
                            card("clock.fill", tint: .white)
                            card("battery.75percent", tint: .green)
                        }
                        .padding(.top, 22)
                        .opacity(isOpen ? 1 : 0)
                    }
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .offset(pointerOffset(phase))
                }
            } animation: { phase in
                switch phase {
                case .away: .easeInOut(duration: 0.7).delay(0.8)
                case .over: .easeInOut(duration: 0.7)
                case .open: .spring(duration: 0.5, bounce: 0.2).delay(0.15)
                case .leave: .easeInOut(duration: 0.7).delay(1.4)
                }
            }
        }
    }

    private func pointerOffset(_ phase: Phase) -> CGSize {
        switch phase {
        case .away: CGSize(width: 110, height: 110)
        case .over, .open: CGSize(width: 6, height: 6)
        case .leave: CGSize(width: 130, height: 118)
        }
    }

    private func card(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(0.1))
            .frame(width: 72, height: 54)
            .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint))
    }
}

/// Activités : la musique s'affiche autour de l'encoche, puis un minuteur devient une bulle.
struct ActivitiesDemo: View {
    private enum Phase: CaseIterable { case idle, music, bubble }

    var body: some View {
        DemoScreen {
            PhaseAnimator(Phase.allCases) { phase in
                let compact = phase != .idle
                let width = compact ? OnboardingDemoLayout.compact.width : OnboardingDemoLayout.idle.width
                HStack(spacing: 5) {
                    DemoNotch(size: CGSize(width: width, height: OnboardingDemoLayout.idle.height)) {
                        DemoMusicActivity().opacity(compact ? 1 : 0)
                    }
                    // Bulle d'une seconde activité, comme sur l'iPhone.
                    DemoNotch(size: CGSize(width: 26, height: OnboardingDemoLayout.idle.height)) {
                        Image(systemName: "timer")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    .opacity(phase == .bubble ? 1 : 0)
                    .scaleEffect(phase == .bubble ? 1 : 0.4, anchor: .top)
                }
                // La bulle occupe sa place même invisible : décalage fixe pour garder l'encoche au centre.
                .offset(x: (26 + 5) / 2)
            } animation: { phase in
                .spring(duration: 0.6, bounce: 0.25).delay(phase == .idle ? 0.6 : 1.3)
            }
        }
    }
}

/// Fichiers : un document glisse vers l'encoche, qui propose l'étagère et AirDrop.
struct FilesDemo: View {
    private enum Phase: CaseIterable { case start, dragging, dropped }

    var body: some View {
        DemoScreen {
            PhaseAnimator(Phase.allCases) { phase in
                let isOpen = phase != .start
                ZStack(alignment: .top) {
                    DemoNotch(size: isOpen ? OnboardingDemoLayout.expanded : OnboardingDemoLayout.idle, isExpanded: isOpen) {
                        HStack(spacing: 10) {
                            zone("tray.and.arrow.down.fill", color: .green, highlighted: phase == .dropped)
                            zone("dot.radiowaves.left.and.right", color: .blue, highlighted: false)
                        }
                        .padding(.top, 22)
                        .opacity(isOpen ? 1 : 0)
                    }
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .offset(documentOffset(phase))
                        .opacity(phase == .dropped ? 0 : 1)
                        .scaleEffect(phase == .dropped ? 0.5 : 1)
                }
            } animation: { phase in
                switch phase {
                case .start: .easeInOut(duration: 0.6).delay(0.9)
                case .dragging: .spring(duration: 0.8, bounce: 0.15)
                case .dropped: .easeOut(duration: 0.35).delay(0.6)
                }
            }
        }
    }

    private func documentOffset(_ phase: Phase) -> CGSize {
        switch phase {
        case .start: CGSize(width: -130, height: 100)
        case .dragging, .dropped: CGSize(width: -58, height: 44)
        }
    }

    private func zone(_ symbol: String, color: Color, highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(highlighted ? 0.45 : 0.2))
            .frame(width: 112, height: 56)
            .overlay(Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(color))
    }
}

/// Illustration simple (symbole) pour les étapes sans démonstration.
struct SymbolDemo: View {
    let symbol: String
    var tint: Color = .white

    var body: some View {
        DemoScreen {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
