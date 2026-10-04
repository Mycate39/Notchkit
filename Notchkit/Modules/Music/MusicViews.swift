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
