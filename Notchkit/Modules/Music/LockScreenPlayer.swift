import SwiftUI

// Lecteurs de l'écran verrouillé, au choix :
// - grand lecteur (par défaut) : pochette au milieu de l'écran, sous l'heure de macOS, puis panneau en
//   verre avec titre, progression et commandes ; l'encoche reste noire ;
// - dans l'encoche : l'activité musique s'élargit sur les côtés de l'encoche, sans descendre (l'heure
//   de macOS, juste en dessous, ne peut pas être déplacée), pochette et titre à gauche, commandes et
//   barres de son à droite.

/// Lecteur de la musique sur l'écran verrouillé.
enum LockScreenPlayerStyle: String, CaseIterable, Identifiable, Sendable {
    case large, notch, off
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .large: "Grand lecteur"
        case .notch: "Dans l'encoche"
        case .off: "Aucun"
        }
    }

    /// Réglage enregistré ; l'ancien interrupteur (`lockScreenPlayerKey`) désactivé donne « Aucun ».
    static func stored(style: String?, legacyEnabled: Bool?) -> LockScreenPlayerStyle {
        if let style, let value = LockScreenPlayerStyle(rawValue: style) { return value }
        return legacyEnabled == false ? .off : .large
    }
}

extension MusicModule {
    static let lockScreenPlayerKey = "module.music.lockScreenPlayer"
    static let lockScreenStyleKey = "module.music.lockScreenStyle"

    /// Réglage du module (grand lecteur par défaut).
    var lockScreenStyle: LockScreenPlayerStyle {
        LockScreenPlayerStyle.stored(style: UserDefaults.standard.string(forKey: Self.lockScreenStyleKey),
                                     legacyEnabled: UserDefaults.standard.object(forKey: Self.lockScreenPlayerKey) as? Bool)
    }

    func lockScreenMedia() -> AnyView? {
        guard lockScreenStyle == .large, let nowPlaying else { return nil }
        return AnyView(LockScreenMediaView(module: self, info: nowPlaying))
    }

    func lockScreenLeading() -> AnyView? {
        guard lockScreenStyle == .notch, let nowPlaying else { return nil }
        return AnyView(LockScreenNowPlaying(info: nowPlaying))
    }

    func lockScreenTrailing() -> AnyView? {
        guard lockScreenStyle == .notch, let nowPlaying else { return nil }
        return AnyView(
            HStack(spacing: 12) {
                LockScreenControls(module: self, isPlaying: nowPlaying.isPlaying,
                                   isReachable: !nowPlaying.resumesInApp)
                // Barres de son, comme l'activité musique repliée.
                EqualizerView(isAnimating: nowPlaying.isPlaying, monitor: reactiveEqualizer ? spectrum : nil,
                              color: ArtworkTint.color(for: nowPlaying), spacingRatio: 1, bellShaped: true)
                    .frame(width: 26)
                    .padding(.vertical, 1)
            }
        )
    }
}

/// Précédent, lecture/pause, suivant. Un lecteur sorti de « À l'écoute » en pause (Deezer, navigateurs)
/// ne reçoit plus aucune commande, et son app ne peut pas s'ouvrir sur l'écran verrouillé : les
/// boutons sont alors grisés et inactifs.
private struct LockScreenControls: View {
    let module: MusicModule
    let isPlaying: Bool
    let isReachable: Bool

    var body: some View {
        HStack(spacing: 12) {
            control("backward.fill", size: 13, help: "Morceau précédent") { module.send(.previousTrack) }
            control(isPlaying ? "pause.fill" : "play.fill", size: 18, help: isPlaying ? "Pause" : "Lecture") {
                module.send(.togglePlayPause)
            }
            .frame(width: 22)  // largeur fixe : lecture et pause n'ont pas la même chasse
            control("forward.fill", size: 13, help: "Morceau suivant") { module.send(.nextTrack) }
        }
        .disabled(!isReachable)
        .opacity(isReachable ? 1 : 0.35)
        .help(isReachable ? Text(verbatim: "") : Text("Reprenez la lecture dans l'app après avoir déverrouillé le Mac"))
    }

    private func control(_ symbol: String, size: CGFloat, help: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlyphButtonStyle())
        .accessibilityLabel(Text(help))
    }
}

/// Pochette, titre et artiste, sur la hauteur de l'encoche.
private struct LockScreenNowPlaying: View {
    let info: NowPlayingInfo

    var body: some View {
        HStack(spacing: 7) {
            IslandArtworkView(info: info)
            VStack(alignment: .leading, spacing: 0) {
                Text(info.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                if let artist = info.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Grand lecteur de l'écran verrouillé : pochette, puis panneau en verre avec le titre, la progression
/// et les commandes. Comme sur l'iPhone, un clic sur la pochette la fait rentrer dans le panneau, à
/// côté du titre ; un clic sur la petite pochette la fait ressortir. Tailles et place :
/// `NotchLayout.lockScreenMedia(screen:)`.
struct LockScreenMediaView: View {
    let module: MusicModule
    let info: NowPlayingInfo
    @Environment(\.lockScreenMedia) private var layout
    @Namespace private var artworkSpace
    /// Dernier clic sur la pochette : un double clic ne la fait pas rentrer puis ressortir aussitôt.
    @State private var lastToggle = Date.distantPast

    private var artworkExpanded: Bool { module.lockScreenArtworkExpanded }

    var body: some View {
        VStack(spacing: layout.gap) {
            if artworkExpanded {
                artwork(side: layout.artwork)
            }
            panel
                .frame(width: layout.panel.width,
                       height: artworkExpanded ? layout.panel.height : layout.compactPanelHeight)
        }
        // Panneau collé au bas de la fenêtre : il reste en place, la pochette descend s'y ranger.
        .frame(maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white)
    }

    /// Pochette cliquable, à la taille donnée ; le même identifiant fait glisser la grande vers la
    /// petite et inversement.
    private func artwork(side: CGFloat) -> some View {
        GeometryReader { proxy in
            let current = min(proxy.size.width, proxy.size.height)
            ArtworkView(info: info, size: current, cornerRadius: NotchLayout.lockScreenArtworkRadius(side: current))
                .shadow(color: .black.opacity(0.4), radius: current * 0.057, y: current * 0.024)
        }
        .matchedGeometryEffect(id: "artwork", in: artworkSpace)
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture {
            guard Date().timeIntervalSince(lastToggle) > NotchLayout.lockScreenArtworkToggleInterval else { return }
            lastToggle = Date()
            Haptics.play(.tap)
            withAnimation(NotchLayout.spring) { module.lockScreenArtworkExpanded.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(artworkExpanded ? Text("Réduire la pochette") : Text("Agrandir la pochette"))
    }

    private var equalizer: some View {
        EqualizerView(isAnimating: info.isPlaying, monitor: module.reactiveEqualizer ? module.spectrum : nil,
                      color: ArtworkTint.color(for: info), spacingRatio: 1, bellShaped: true)
            .frame(width: 22, height: 16)
    }

    @ViewBuilder
    private var header: some View {
        if artworkExpanded {
            VStack(spacing: 2) { titles }
                .lineLimit(1)
                .padding(.horizontal, 34)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { equalizer }
        } else {
            // Pochette rentrée : petite pochette, titre et artiste alignés à gauche, barres de son à droite.
            HStack(spacing: 12) {
                artwork(side: layout.smallArtwork)
                VStack(alignment: .leading, spacing: 2) { titles }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                equalizer
            }
        }
    }

    @ViewBuilder
    private var titles: some View {
        Text(info.title)
            .font(.system(size: 15, weight: .semibold))
        if let artist = info.artist, !artist.isEmpty {
            Text(artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var panel: some View {
        let reachable = !info.resumesInApp
        return VStack(spacing: 10) {
            header
            if info.duration != nil {
                PlaybackProgressView(info: info, fontSize: 10, barHeight: 5) { module.send(.seek($0)) }
            }
            HStack(spacing: 0) {
                // Emplacement vide de la largeur du bouton AirPlay : les commandes restent centrées.
                Color.clear.frame(width: 22, height: 22)
                Spacer(minLength: 4)
                PlaybackControls(module: module, isPlaying: info.isPlaying, spacing: 34, glyphs: (side: 20, main: 26))
                    .disabled(!reachable)
                    .opacity(reachable ? 1 : 0.35)
                Spacer(minLength: 4)
                AirPlayButton()
                    .frame(width: 22, height: 22)
                    .help("Sortie audio")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .modifier(LockScreenGlassPanel())
    }
}

/// Panneau en verre du grand lecteur. Au-dessus de l'écran verrouillé, aucun verre ni flou de macOS ne
/// voit le fond (vérifié sur le vrai écran verrouillé : voile gris uniforme), mais la transparence, elle,
/// fonctionne : le panneau est un verre transparent sans flou. Voile sombre léger (le fond d'écran, même
/// une vidéo aérienne, reste visible et bouge derrière), reflet clair sur le bord et éclat en haut ; une
/// ombre fine garde les textes lisibles.
private struct LockScreenGlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchLayout.lockScreenPanelRadius, style: .continuous)
        content
            .modifier(GlassLegibility(active: true))
            .background {
                if NotchAccessibility.reduceTransparency {
                    shape.fill(Color(white: 0.15))
                } else {
                    // Voile plus dense en bas, comme un verre teinté éclairé par le haut.
                    shape.fill(LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.32)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay {
                // Reflet du verre : bord clair, plus vif en haut à gauche, et éclat sur le haut.
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.12), .white.opacity(0.35)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                shape.fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
    }
}

/// Réglage du lecteur, dans la page du module Musique.
struct LockScreenPlayerSetting: View {
    @AppStorage(MusicModule.lockScreenStyleKey) private var style = ""
    @AppStorage(MusicModule.lockScreenPlayerKey) private var legacyEnabled = true

    var body: some View {
        Picker("Lecteur sur l'écran verrouillé", selection: Binding(
            get: { LockScreenPlayerStyle.stored(style: style.isEmpty ? nil : style, legacyEnabled: legacyEnabled) },
            set: { style = $0.rawValue }
        )) {
            ForEach(LockScreenPlayerStyle.allCases) { Text($0.title).tag($0) }
        }
        Text("Grand lecteur : la pochette et les commandes au milieu de l'écran verrouillé, sous l'heure. Dans l'encoche : l'encoche s'élargit avec le morceau en cours et ses commandes.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
