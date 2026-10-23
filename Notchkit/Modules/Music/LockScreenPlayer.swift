import SwiftUI

// Lecteur de l'écran verrouillé : quand le Mac est verrouillé, l'activité musique s'élargit sur les
// côtés de l'encoche, sans descendre (l'heure de macOS, juste en dessous, ne peut pas être déplacée).
// Pochette et titre à gauche, commandes et barres de son à droite : seul endroit cliquable de
// l'encoche verrouillée.

extension MusicModule {
    static let lockScreenPlayerKey = "module.music.lockScreenPlayer"

    /// Réglage du module (activé par défaut).
    var showsLockScreenPlayer: Bool {
        UserDefaults.standard.object(forKey: Self.lockScreenPlayerKey) as? Bool ?? true
    }

    func lockScreenLeading() -> AnyView? {
        guard showsLockScreenPlayer, let nowPlaying else { return nil }
        return AnyView(LockScreenNowPlaying(info: nowPlaying))
    }

    func lockScreenTrailing() -> AnyView? {
        guard showsLockScreenPlayer, let nowPlaying else { return nil }
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

/// Réglage du lecteur, dans la page du module Musique.
struct LockScreenPlayerSetting: View {
    @AppStorage(MusicModule.lockScreenPlayerKey) private var isOn = true

    var body: some View {
        Toggle("Lecteur sur l'écran verrouillé", isOn: $isOn)
        Text("Quand le Mac est verrouillé, l'encoche s'élargit avec le morceau en cours et ses commandes. Ce sont les seuls boutons actifs de l'encoche verrouillée.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
