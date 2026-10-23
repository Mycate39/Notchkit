import AVFoundation
import SwiftUI

/// Alertes agrandies (façon Dynamic Island) pour le déverrouillage et l'authentification.
enum UnlockAnimations {
    static let size = CGSize(width: 220, height: 118)

    /// Carré façon Dynamic Island de l'animation Face ID : le cercle occupe 48 % de sa largeur, coins
    /// du bas arrondis au cinquième du côté (proportions de l'animation d'origine).
    static let faceIDSize = CGSize(width: 200, height: 200)

    @MainActor
    static func unlocked() -> NotchAlert {
        var alert = NotchAlert(duration: .seconds(2.1), expandedContent: AnyView(FaceIDUnlockView()),
                               expandedSize: faceIDSize)
        alert.centersExpandedContent = true
        alert.expandedCornerRadius = faceIDSize.width / 5
        return alert
    }

    @MainActor
    static func touchID(duration: Duration = .seconds(60)) -> NotchAlert {
        NotchAlert(duration: duration, expandedContent: AnyView(TouchIDPromptView()), expandedSize: size)
    }

    @MainActor
    static func password(duration: Duration = .seconds(120)) -> NotchAlert {
        NotchAlert(duration: duration, expandedContent: AnyView(PasswordPromptView()), expandedSize: size)
    }
}

/// Déverrouillage façon Face ID de la Dynamic Island : des anneaux verts tournent (le visage est lu),
/// se rassemblent en un cercle, puis une coche s'y trace. Vidéo HEVC avec transparence
/// (`FaceIDUnlock.mov`, 408 × 408 px, 2 s) rendue depuis une animation Lottie (moteur SVG, pour garder
/// son flou de mouvement), épaisseurs d'origine,
/// fond retiré (c'est l'encoche qui s'agrandit), recadrée sur le logo : le cercle en occupe 70,6 %.
struct FaceIDUnlockView: View {
    /// Taille de la vidéo, en points.
    static let videoSize = CGSize(width: 136, height: 136)
    /// Instant où la coche est entièrement tracée (image fixe si les animations sont réduites).
    static let checkedTime = 1.45

    var body: some View {
        TransparentVideo(resource: "FaceIDUnlock", stillAt: NotchAccessibility.reduceMotion ? Self.checkedTime : nil)
            .frame(width: Self.videoSize.width, height: Self.videoSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(Text("Déverrouillé"))
    }
}

/// Lecture unique d'une vidéo du paquet de l'app, transparence comprise (couche AVPlayerLayer non opaque).
private struct TransparentVideo: NSViewRepresentable {
    let resource: String
    /// Instant à afficher sans lecture (`nil` : lecture normale).
    var stillAt: Double?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mov") else { return view }
        let player = AVPlayer(url: url)
        player.isMuted = true
        // Vidéo sans piste audio : elle ne touche ni à la musique ni à « À l'écoute ».
        player.preventsDisplaySleepDuringVideoPlayback = false
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.isOpaque = false
        layer.backgroundColor = .clear
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        if let stillAt {
            player.seek(to: CMTime(seconds: stillAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.play()
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        for layer in view.layer?.sublayers ?? [] {
            (layer as? AVPlayerLayer)?.player?.pause()
        }
    }
}

/// Demande Touch ID : empreinte rose avec des ondes qui s'élargissent.
struct TouchIDPromptView: View {
    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(paused: NotchAccessibility.reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3) { index in
                        let phase = (time / 1.5 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Self.pink.opacity((1 - phase) * 0.7), lineWidth: 1.5)
                            .frame(width: 34 + phase * 34, height: 34 + phase * 34)
                    }
                    Image(systemName: "touchid")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Self.pink)
                        .opacity(0.75 + 0.25 * sin(time * 4))
                }
            }
            .frame(height: 60)
            Text("Touch ID")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    static let pink = Color(red: 1, green: 0.22, blue: 0.37)
}

/// Demande de mot de passe : cadenas et points qui s'allument l'un après l'autre.
struct PasswordPromptView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.white)
                .symbolEffect(.pulse)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate * 4) % 6
                HStack(spacing: 7) {
                    ForEach(0..<6) { index in
                        Circle()
                            .fill(.white.opacity(index <= step ? 0.95 : 0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: step)
            }
            Text("Mot de passe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Carte et réglages

struct UnlockExpandedView: View {
    let module: UnlockModule

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "touchid")
                .font(.system(size: 26))
            Text("Animations de déverrouillage actives")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UnlockSettingsView: View {
    @Bindable var module: UnlockModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Animation Touch ID au déverrouillage du Mac", isOn: $module.animateUnlock)
            Toggle("Animation pendant une demande Touch ID", isOn: $module.animateTouchID)
            Toggle("Animation pendant une demande de mot de passe", isOn: $module.animatePassword)
            Text("Animations visuelles uniquement : Notchkit ne lit pas votre empreinte. macOS n'indique pas comment la session a été déverrouillée et rien ne peut s'afficher sur l'écran verrouillé : l'animation Touch ID se joue juste après le déverrouillage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
