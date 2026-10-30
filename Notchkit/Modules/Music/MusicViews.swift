import AppKit
import AVKit
import SwiftUI

// MARK: - Pochette

/// Pochette du morceau ; à défaut, l'icône de l'app qui joue ; à défaut, une note de musique.
struct ArtworkView: View {
    let info: NowPlayingInfo
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let icon = AppIconCache.icon(for: info.bundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
                    .background(.white.opacity(0.08))
            } else {
                DefaultArtwork()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Fondu quand la pochette change de morceau.
        .animation(.easeInOut(duration: 0.25), value: info.artworkHash)
    }
}

/// Pochette de l'île : carré arrondi qui occupe toute la hauteur disponible.
struct IslandArtworkView: View {
    let info: NowPlayingInfo

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ArtworkView(info: info, size: side, cornerRadius: side * 0.24)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Couleur des barres de l'île, tirée de la pochette (moyenne éclaircie), mise en cache par pochette.
@MainActor
enum ArtworkTint {
    private static var cache: [Int: NSColor] = [:]

    static func color(for info: NowPlayingInfo) -> NSColor {
        guard let artwork = info.artwork, let hash = info.artworkHash else { return .white }
        if let cached = cache[hash] { return cached }
        let color = tint(from: artwork) ?? .white
        if cache.count > 32 { cache.removeAll() }
        cache[hash] = color
        return color
    }

    /// Moyenne de l'image (réduite à 1 × 1 pixel), puis éclaircie et légèrement désaturée
    /// pour rester lisible sur fond noir.
    static func tint(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation, 0.45), brightness: max(brightness, 0.82), alpha: 1)
    }
}

/// Icônes d'apps, mises en cache (la recherche sur disque n'est faite qu'une fois par app).
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = cache[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleIdentifier] = icon
        return icon
    }
}

// MARK: - Vue étendue

struct MusicExpandedView: View {
    let module: MusicModule
    @Environment(\.widgetSize) private var size
    @Environment(\.widgetOwnsNotchSize) private var ownsNotchSize
    @AppStorage(MusicPlayerStyle.key) private var playerStyle = MusicPlayerStyle.large.rawValue

    /// Rien ne joue : le lecteur reste en place, vide, commandes grisées.
    private static var emptyInfo: NowPlayingInfo {
        NowPlayingInfo(origin: .mediaRemote, title: String(localized: "Aucune lecture en cours"), isPlaying: false)
    }

    var body: some View {
        let info = module.nowPlaying ?? Self.emptyInfo
        let isEmpty = module.nowPlaying == nil
        Group {
            if ownsNotchSize {
                // Seul sur sa page : l'encoche s'ouvre en petit lecteur serré autour de la caméra.
                compactPlayerLayout(info, isEmpty: isEmpty)
            } else if size == .small {
                // Petit widget : pochette, titre et commandes empilés. Du plus complet au plus serré,
                // selon la hauteur de la carte (taille de l'encoche).
                ViewThatFits(in: .vertical) {
                    smallLayout(info, artworkSize: 52, isEmpty: isEmpty)
                    smallLayout(info, artworkSize: 36, isEmpty: isEmpty)
                    smallLayout(info, artworkSize: nil, isEmpty: isEmpty)
                }
                .padding(8)
            } else {
                // Moyen et grand : présentation façon Dynamic Island de l'iPhone, resserrée si la carte est basse.
                ViewThatFits(in: .vertical) {
                    if size == .large {
                        islandLayout(info, artworkSize: 60, showsProgress: true, largeControls: true, isEmpty: isEmpty)
                    }
                    islandLayout(info, artworkSize: size == .large ? 50 : 46, showsProgress: true, largeControls: true,
                                 isEmpty: isEmpty)
                    islandLayout(info, artworkSize: 40, showsProgress: true, largeControls: false, isEmpty: isEmpty)
                    islandLayout(info, artworkSize: 36, showsProgress: false, largeControls: false, isEmpty: isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    /// Petit lecteur (encoche à la taille `NotchLayout.musicPlayerSize`), sur trois lignes : petite
    /// pochette, titre et artiste, barres de son ; barre de lecture fine entre ses deux temps ;
    /// aléatoire, précédent, lecture, suivant et répétition.
    private func compactPlayerLayout(_ info: NowPlayingInfo, isEmpty: Bool) -> some View {
        // Mêmes éléments aux deux tailles, à l'échelle du réglage (`MusicPlayerStyle.scale`).
        let k = (MusicPlayerStyle(rawValue: playerStyle) ?? .large).scale
        return VStack(spacing: 7 * k) {
            HStack(spacing: 8 * k) {
                Button { module.openPlayerApp() } label: {
                    ArtworkView(info: info, size: 26 * k, cornerRadius: 6 * k)
                }
                .buttonStyle(.notch)
                .disabled(isEmpty)
                .help("Ouvrir l'app qui joue")

                VStack(alignment: .leading, spacing: 0) {
                    Text(info.title)
                        .font(.system(size: 11 * k, weight: .semibold))
                    if let artist = info.artist {
                        Text(artist)
                            .font(.system(size: 10 * k, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth, value: info.title)

                EqualizerView(isAnimating: info.isPlaying, monitor: module.reactiveEqualizer ? module.spectrum : nil,
                              color: ArtworkTint.color(for: info), spacingRatio: 1, bellShaped: true)
                    .frame(width: 18 * k, height: 12 * k)
            }

            if info.duration != nil {
                PlaybackProgressView(info: info, fontSize: 10 * k, barHeight: 3 * k) { module.send(.seek($0)) }
            }

            HStack(spacing: 0) {
                modeButton("shuffle", scale: k, help: "Lecture aléatoire") { module.send(.toggleShuffle) }
                Spacer(minLength: 4)
                PlaybackControls(module: module, isPlaying: info.isPlaying, spacing: 22 * k,
                                 glyphs: (side: 15 * k, main: 19 * k))
                Spacer(minLength: 4)
                modeButton("repeat", scale: k, help: "Répéter") { module.send(.toggleRepeat) }
            }
            .inactive(isEmpty)
        }
    }

    private func modeButton(_ symbol: String, scale k: CGFloat, help: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * k, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22 * k, height: 22 * k)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlyphButtonStyle())
        .help(help)
        .accessibilityLabel(Text(help))
    }

    /// Lecteur de l'iPhone (ancienne présentation en grand, 440 × 222 pt) : grande pochette,
    /// titre et artiste en gros, barre et temps lisibles, gros glyphes largement espacés.
    private func playerLayout(_ info: NowPlayingInfo, isEmpty: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { module.openPlayerApp() } label: {
                    ArtworkView(info: info, size: 64, cornerRadius: 64 * 0.22)
                }
                .buttonStyle(.notch)
                .disabled(isEmpty)
                .help("Ouvrir l'app qui joue")

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 17, weight: .bold))
                    if let artist = info.artist {
                        Text(artist)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth, value: info.title)

                EqualizerView(isAnimating: info.isPlaying, monitor: module.reactiveEqualizer ? module.spectrum : nil,
                              color: ArtworkTint.color(for: info), spacingRatio: 1, bellShaped: true)
                    .frame(width: 26, height: 20)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            }
            .frame(height: 64)

            Spacer(minLength: 10)
            if info.duration != nil {
                PlaybackProgressView(info: info, fontSize: 12, barHeight: 6) { module.send(.seek($0)) }
            }
            Spacer(minLength: 10)

            HStack(spacing: 0) {
                Color.clear.frame(width: 28, height: 1)
                Spacer(minLength: 4)
                PlaybackControls(module: module, isPlaying: info.isPlaying, spacing: 46, glyphs: (side: 26, main: 34))
                    .inactive(isEmpty)
                Spacer(minLength: 4)
                AirPlayButton()
                    .frame(width: 24, height: 24)
                    .frame(width: 28, height: 28)
                    .help("Sortie audio")
            }
        }
        .padding(.vertical, 2)
    }

    private func smallLayout(_ info: NowPlayingInfo, artworkSize: CGFloat?, isEmpty: Bool) -> some View {
        VStack(spacing: 6) {
            if let artworkSize {
                Button { module.openPlayerApp() } label: {
                    ArtworkView(info: info, size: artworkSize, cornerRadius: artworkSize * 0.2)
                }
                .buttonStyle(.notch)
                .disabled(isEmpty)
            }
            VStack(spacing: 0) {
                Text(info.title)
                    .font(.system(size: 11, weight: .semibold))
                if let artist = info.artist {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            PlaybackControls(module: module, isPlaying: info.isPlaying, compact: true)
                .inactive(isEmpty)
        }
    }

    private func islandLayout(_ info: NowPlayingInfo, artworkSize: CGFloat, showsProgress: Bool,
                              largeControls: Bool, isEmpty: Bool) -> some View {
        // Présentation des Live Activities de l'iPhone : pochette, titre en gras et barres en haut,
        // barre fine au milieu, glyphes blancs sans fond en bas.
        VStack(spacing: largeControls ? 10 : 6) {
            HStack(spacing: 12) {
                Button {
                    module.openPlayerApp()
                } label: {
                    ArtworkView(info: info, size: artworkSize, cornerRadius: artworkSize * 0.22)
                        .overlay(alignment: .bottomTrailing) {
                            // Petite icône de l'app qui joue (désactivable dans les réglages).
                            if module.showAppBadge, info.artwork != nil, let icon = AppIconCache.icon(for: info.bundleIdentifier) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .offset(x: 4, y: 4)
                            }
                        }
                }
                .buttonStyle(.notch)
                .disabled(isEmpty)
                .help("Ouvrir l'app qui joue")

                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title)
                        .font(.system(size: 16, weight: .bold))
                    if let artist = info.artist {
                        Text(artist)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth, value: info.title)

                // Barres colorées d'après la pochette, en haut à droite.
                EqualizerView(isAnimating: info.isPlaying, monitor: module.reactiveEqualizer ? module.spectrum : nil,
                              color: ArtworkTint.color(for: info), spacingRatio: 1, bellShaped: true)
                    .frame(width: 24, height: 18)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)
            }
            .frame(height: artworkSize)

            if showsProgress, info.duration != nil {
                PlaybackProgressView(info: info) { module.send(.seek($0)) }
            }

            // Commandes centrées, AirPlay à droite : un emplacement vide de même largeur à gauche
            // garde les commandes au centre sans jamais chevaucher le bouton AirPlay.
            HStack(spacing: 0) {
                Color.clear.frame(width: 26, height: 1)
                Spacer(minLength: 4)
                PlaybackControls(module: module, isPlaying: info.isPlaying, large: largeControls,
                                 spacing: size == .large ? 34 : 24)
                    .inactive(isEmpty)
                Spacer(minLength: 4)
                AirPlayButton()
                    .frame(width: 22, height: 22)
                    .frame(width: 26, height: 26)
                    .help("Sortie audio")
            }
        }
    }
}

private extension View {
    /// Commandes grisées et sans effet (aucun morceau à commander).
    func inactive(_ inactive: Bool) -> some View {
        disabled(inactive).opacity(inactive ? 0.35 : 1)
    }
}

/// Barre de progression et temps écoulé/restant.
/// Ne se rafraîchit qu'une fois par seconde, et seulement quand l'encoche est dépliée.
struct PlaybackProgressView: View {
    let info: NowPlayingInfo
    var fontSize: CGFloat = 11
    var barHeight: CGFloat = 5
    /// Glisser la barre change le moment du morceau (comme sur l'iPhone) ; `nil` : barre figée.
    var onSeek: ((TimeInterval) -> Void)?

    /// Position suivie pendant le glissement (fraction du morceau), `nil` au repos.
    @State private var scrub: Double?

    var body: some View {
        // Barre continue pendant la lecture (et pendant un glissement), à l'arrêt rien ne bouge.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !info.isPlaying && scrub == nil)) { context in
            let duration = info.duration ?? 0
            let elapsed = scrub.map { $0 * duration } ?? info.elapsed(at: context.date)

            HStack(spacing: 10) {
                Text(elapsed.map(Self.format) ?? "–:––")
                    .frame(minWidth: 30, alignment: .leading)
                ProgressLine(value: duration > 0 ? (elapsed ?? 0) / duration : 0, height: barHeight,
                             isScrubbing: scrub != nil)
                    .opacity(elapsed == nil ? 0.4 : 1)
                    .overlay { scrubArea(duration: duration) }
                Text(elapsed.map { "-" + Self.format(max(0, duration - $0)) } ?? Self.format(duration))
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(.system(size: fontSize, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(scrub == nil ? 0.5 : 0.85))
        }
    }

    /// Zone de glissement : plus haute que la barre, pour la viser sans précision.
    @ViewBuilder
    private func scrubArea(duration: TimeInterval) -> some View {
        if let onSeek, duration > 0, !info.resumesInApp {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = Self.fraction(x: value.location.x, width: proxy.size.width)
                                withAnimation(.snappy(duration: 0.2)) { scrub = fraction }
                            }
                            .onEnded { value in
                                let fraction = Self.fraction(x: value.location.x, width: proxy.size.width)
                                onSeek(fraction * duration)
                                withAnimation(.snappy(duration: 0.2)) { scrub = nil }
                            }
                    )
            }
            .frame(height: max(barHeight, 22))
            .accessibilityLabel(Text("Position dans le morceau"))
        }
    }

    /// Fraction du morceau sous le pointeur, bornée à la barre.
    nonisolated static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded(.down))).formatted(.time(pattern: .minuteSecond))
    }
}

/// Barre de progression fine : partie écoulée claire sur fond gris sombre, comme sur l'iPhone.
/// Pendant un glissement, elle s'épaissit et passe au blanc.
private struct ProgressLine: View {
    var value: Double
    var height: CGFloat = 5
    var isScrubbing = false

    /// Dessinée d'un bloc (`Canvas`) : sa largeur ne doit suivre aucune animation venue d'ailleurs.
    /// Avec des cadres SwiftUI, le ressort « rebondissant » du changement de page étirait la partie
    /// écoulée en revenant sur la page Musique.
    var body: some View {
        Canvas { context, size in
            let fraction = min(max(value, 0), 1)
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.fill(track, with: .color(.white.opacity(0.18)))
            guard fraction > 0 else { return }
            // Jamais plus étroite qu'un cercle, pour garder des bouts arrondis.
            let width = max(size.height, size.width * fraction)
            let elapsed = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: size.height),
                               cornerRadius: size.height / 2)
            context.fill(elapsed, with: .color(.white.opacity(isScrubbing ? 1 : 0.8)))
        }
        .frame(height: height)
        // Épaissie sans changer la mise en page autour.
        .scaleEffect(x: 1, y: isScrubbing ? 1.8 : 1)
    }
}

struct PlaybackControls: View {
    let module: MusicModule
    let isPlaying: Bool
    /// Petit widget : boutons serrés.
    var compact = false
    /// Grands glyphes (sinon taille intermédiaire, pour les cartes basses).
    var large = true
    var spacing: CGFloat = 34
    /// Retour haptique du trackpad à chaque appui (commandes de la bulle).
    var haptics = false
    /// Tailles imposées des glyphes (lecteur de l'encoche en verre).
    var glyphs: (side: CGFloat, main: CGFloat)?

    // Glyphes blancs pleins, sans fond ; lecture/pause plus grand que précédent/suivant.
    var body: some View {
        let side: CGFloat = glyphs?.side ?? (compact ? 13 : (large ? 22 : 17))
        let main: CGFloat = glyphs?.main ?? (compact ? 18 : (large ? 32 : 24))
        HStack(spacing: compact ? 12 : spacing) {
            control("backward.fill", size: side, help: "Morceau précédent") { module.send(.previousTrack) }
            control(isPlaying ? "pause.fill" : "play.fill", size: main, help: isPlaying ? "Pause" : "Lecture") {
                module.send(.togglePlayPause)
            }
            .frame(width: main * 1.2)  // largeur fixe : lecture et pause n'ont pas la même chasse
            control("forward.fill", size: side, help: "Morceau suivant") { module.send(.nextTrack) }
        }
    }

    private func control(_ symbol: String, size: CGFloat, help: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button {
            if haptics { Haptics.play(.tap) }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlyphButtonStyle())
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// Commandes sorties à droite de la bulle de la musique, au survol.
struct BubblePlaybackControls: View {
    let module: MusicModule
    let isPlaying: Bool

    var body: some View {
        PlaybackControls(module: module, isPlaying: isPlaying, compact: true, haptics: true)
    }
}

/// Bouton AirPlay de macOS (choix de la sortie audio), via `AVRoutePickerView` (API publique).
struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = FirstClickRoutePicker()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.white.withAlphaComponent(0.55), for: .normal)
        picker.setRoutePickerButtonColor(.white, for: .normalHighlighted)
        // Sortie AirPlay en cours : symbole ambre, comme les autres états actifs.
        let amber = NSColor(StandBy.amber)
        picker.setRoutePickerButtonColor(amber, for: .active)
        picker.setRoutePickerButtonColor(amber.withAlphaComponent(0.8), for: .activeHighlighted)
        return picker
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}

/// Bouton AirPlay qui répond au premier clic. Dans une fenêtre qui n'est pas au premier plan (grand
/// lecteur de l'écran verrouillé), le bouton interne de macOS ne servait qu'à activer la fenêtre : un
/// clic sur deux était perdu, et un double clic ouvrait puis refermait aussitôt le menu des sorties.
private final class FirstClickRoutePicker: AVRoutePickerView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Le clic arrive ici plutôt qu'au bouton interne, qui refuse le premier clic.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        // Second clic d'un double clic : le menu est déjà ouvert, on ne le referme pas.
        guard event.clickCount == 1 else { return }
        if let button = Self.button(in: self) {
            button.performClick(nil)
        } else {
            super.mouseDown(with: event)
        }
    }

    private static func button(in view: NSView) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton { return button }
            if let button = button(in: subview) { return button }
        }
        return nil
    }
}

// MARK: - Réglages

struct MusicSettingsView: View {
    @Bindable var module: MusicModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Afficher le morceau quand l'encoche est repliée", isOn: $module.showInCompact)
            Toggle("Afficher l'icône de l'app sur la pochette", isOn: $module.showAppBadge)
            MusicPlayerStyleSetting()
            LockScreenPlayerSetting()
            Toggle("Barres réactives au son (temps réel)", isOn: $module.reactiveEqualizer)
            Text("Analyse le son joué par le Mac pour animer les barres. macOS demande l'autorisation « Enregistrement audio du système » et affiche un indicateur pendant l'écoute. Le son n'est ni enregistré ni envoyé.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if module.reactiveEqualizer {
                SpectrumStatusView(monitor: module.spectrum)
            }
            Toggle("Détecter toutes les apps (expérimental)", isOn: $module.useMediaRemote)
            Text("Nécessaire pour Deezer, les navigateurs et la plupart des lecteurs. Utilise une interface non officielle d'Apple qui peut cesser de fonctionner après une mise à jour de macOS ; Music et Spotify restent alors pris en charge.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// État de l'analyse du son, avec un raccourci vers les réglages de confidentialité en cas de souci.
private struct SpectrumStatusView: View {
    let monitor: AudioSpectrumMonitor

    var body: some View {
        switch monitor.status {
        case .stopped:
            EmptyView()
        case .running:
            Label("Analyse du son active", systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.green)
        case .silent:
            VStack(alignment: .leading, spacing: 4) {
                Label("Aucun son capté : l'autorisation a peut-être été refusée.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Ouvrir les réglages de confidentialité") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        case .unsupported:
            Text("Nécessite macOS 14.2 ou plus récent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Text("L'analyse du son n'a pas pu démarrer : \(reason)")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

/// Version mini : pochette et lecture/pause.
struct MusicMiniView: View {
    let module: MusicModule

    var body: some View {
        if let info = module.nowPlaying {
            // Pochette et bouton proportionnels à la taille du widget.
            GeometryReader { proxy in
                // Le bouton a une taille fixe : la pochette prend la hauteur restante.
                let button: StandByButtonStyle.Size = proxy.size.height > 90 ? .regular : .small
                let spacing = proxy.size.height * 0.05
                let side = max(0, min(proxy.size.width * 0.78, proxy.size.height - button.height - spacing - 8))
                VStack(spacing: spacing) {
                    ArtworkView(info: info, size: side, cornerRadius: side * 0.2)
                    Button { module.send(.togglePlayPause) } label: {
                        Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.standBy(button, active: true, circle: true))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            MiniWidget(value: nil, caption: String(localized: "Aucune lecture")) {
                LineGlyph(shape: MusicNoteShape())
            }
        }
    }
}

/// Taille du petit lecteur ouvert sur la page de la musique seule.
struct MusicPlayerStyleSetting: View {
    @AppStorage(MusicPlayerStyle.key) private var style = MusicPlayerStyle.large.rawValue

    var body: some View {
        Picker("Taille du lecteur", selection: $style) {
            ForEach(MusicPlayerStyle.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
    }
}
