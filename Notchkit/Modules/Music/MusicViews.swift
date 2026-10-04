import AppKit
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
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.12))
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

    var body: some View {
        if let info = module.nowPlaying, size == .small {
            // Petit widget : pochette, titre et commandes empilés.
            VStack(spacing: 6) {
                Button { module.openPlayerApp() } label: {
                    ArtworkView(info: info, size: 52, cornerRadius: 10)
                }
                .buttonStyle(.plain)
                VStack(spacing: 0) {
                    Text(info.title)
                        .font(.system(size: 11, weight: .semibold))
                    if let artist = info.artist {
                        Text(artist)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                PlaybackControls(module: module, isPlaying: info.isPlaying, compact: true)
            }
            .padding(8)
        } else if let info = module.nowPlaying {
            HStack(spacing: 12) {
                Button {
                    module.openPlayerApp()
                } label: {
                    ArtworkView(info: info, size: size == .large ? 72 : 56, cornerRadius: 12)
                        .overlay(alignment: .bottomTrailing) {
                            // Petite icône de l'app qui joue, sauf si elle est déjà affichée en grand.
                            if module.showAppBadge, info.artwork != nil, let icon = AppIconCache.icon(for: info.bundleIdentifier) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .offset(x: 5, y: 5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Ouvrir l'app qui joue")

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.title)
                            .font(.system(size: 13, weight: .semibold))
                        if let artist = info.artist {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .lineLimit(1)

                    if info.duration != nil {
                        PlaybackProgressView(info: info)
                    }

                    PlaybackControls(module: module, isPlaying: info.isPlaying)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 22))
                Text("Aucune lecture en cours")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
        }
    }
}

/// Barre de progression et temps écoulé/restant.
/// Ne se rafraîchit qu'une fois par seconde, et seulement quand l'encoche est dépliée.
private struct PlaybackProgressView: View {
    let info: NowPlayingInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = info.duration ?? 0
            let elapsed = info.elapsed(at: context.date)

            VStack(spacing: 3) {
                GeometryReader { proxy in
                    let progress = duration > 0 ? (elapsed ?? 0) / duration : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 4)
                .opacity(elapsed == nil ? 0.4 : 1)

                HStack {
                    Text(elapsed.map(Self.format) ?? "–:––")
                    Spacer()
                    Text(elapsed.map { "-" + Self.format(max(0, duration - $0)) } ?? Self.format(duration))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded(.down))).formatted(.time(pattern: .minuteSecond))
    }
}

private struct PlaybackControls: View {
    let module: MusicModule
    let isPlaying: Bool
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 22) {
            control("backward.fill", size: compact ? 11 : 14, help: "Morceau précédent") { module.send(.previousTrack) }
            control(isPlaying ? "pause.fill" : "play.fill", size: compact ? 16 : 20, help: isPlaying ? "Pause" : "Lecture") {
                module.send(.togglePlayPause)
            }
            control("forward.fill", size: compact ? 11 : 14, help: "Morceau suivant") { module.send(.nextTrack) }
        }
        .frame(maxWidth: .infinity)
    }

    private func control(_ symbol: String, size: CGFloat, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Réglages

struct MusicSettingsView: View {
    @Bindable var module: MusicModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Afficher le morceau quand l'encoche est repliée", isOn: $module.showInCompact)
            Toggle("Afficher l'icône de l'app sur la pochette", isOn: $module.showAppBadge)
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
                let side = min(proxy.size.width * 0.78, proxy.size.height * 0.55)
                VStack(spacing: proxy.size.height * 0.05) {
                    ArtworkView(info: info, size: side, cornerRadius: side * 0.2)
                    Button { module.send(.togglePlayPause) } label: {
                        Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: max(10, side * 0.36), weight: .semibold))
                            .frame(width: side, height: side * 0.5)
                            .contentShape(Rectangle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            MiniWidget(symbol: "music.note", value: nil, caption: String(localized: "Aucune lecture"))
        }
    }
}
