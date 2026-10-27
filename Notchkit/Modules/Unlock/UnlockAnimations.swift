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

    /// Demande Touch ID : même carré que Face ID. `state` passe à « terminé » quand la demande se ferme.
    @MainActor
    static func touchID(state: TouchIDPromptState, duration: Duration = .seconds(60)) -> NotchAlert {
        var alert = NotchAlert(duration: duration, expandedContent: AnyView(TouchIDPromptView(state: state)),
                               expandedSize: faceIDSize)
        alert.centersExpandedContent = true
        alert.expandedCornerRadius = faceIDSize.width / 5
        return alert
    }

    /// Temps laissé à la fin de l'animation Touch ID (empreinte → cercle → coche) avant de refermer.
    static let touchIDFinishDuration: Duration = .milliseconds(1300)

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
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mov") else { return NSView() }
        let player = AVPlayer(url: url)
        player.isMuted = true
        // Vidéo sans piste audio : elle ne touche ni à la musique ni à « À l'écoute ».
        player.preventsDisplaySleepDuringVideoPlayback = false
        let view = VideoHostView(player: player)
        if let stillAt {
            player.seek(to: CMTime(seconds: stillAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.play()
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? VideoHostView)?.stop()
    }
}

/// État partagé d'une demande Touch ID : la demande s'est fermée (doigt reconnu, le plus souvent).
@MainActor
@Observable
final class TouchIDPromptState {
    var finished = false
}

/// Demande Touch ID : l'empreinte apparaît et se remplit en rouge, puis reste affichée tant que macOS
/// attend le doigt. Quand la demande se ferme, elle se transforme en cercle, et le cercle et la coche
/// façon Face ID, en rouge, prennent le relais (dessinés ici, nets à toute taille).
/// Vidéo `TouchIDPrompt.mov` (408 × 408 px, 60 i/s), rendue depuis une animation Lottie : de 0 à 2 s,
/// apparition et remplissage ; de 2 à 2,77 s, transformation en cercle fin (cercle à 70,6 % du cadre).
struct TouchIDPromptView: View {
    let state: TouchIDPromptState

    static let red = Color(red: 232 / 255, green: 76 / 255, blue: 81 / 255)
    /// Pause sur l'empreinte pleine, pendant l'attente.
    private static let holdTime = 2.0
    /// Cercle final : même taille que celui de Face ID (48 % du carré).
    private static let diameter: CGFloat = 96

    @State private var showsCheck = false
    /// Le cercle s'épaissit, du trait fin de la vidéo à celui de Face ID (6,5 % du diamètre).
    @State private var ringWidth: CGFloat = 2
    @State private var check: CGFloat = 0

    var body: some View {
        ZStack {
            StagedVideo(resource: "TouchIDPrompt", holdAt: Self.holdTime, released: state.finished,
                        stillOnly: NotchAccessibility.reduceMotion, onEnd: finish)
                .frame(width: FaceIDUnlockView.videoSize.width, height: FaceIDUnlockView.videoSize.height)
                .opacity(showsCheck ? 0 : 1)
            if showsCheck {
                Circle()
                    .stroke(Self.red, lineWidth: ringWidth)
                    .frame(width: Self.diameter - ringWidth, height: Self.diameter - ringWidth)
                TouchIDCheck()
                    .trim(from: 0, to: check)
                    .stroke(Self.red, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .frame(width: Self.diameter, height: Self.diameter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Touch ID"))
        // Animations réduites : pas de vidéo jouée, la coche apparaît directement à la fin.
        .onChange(of: state.finished) { _, finished in
            if finished && NotchAccessibility.reduceMotion { finish() }
        }
    }

    private func finish() {
        guard !showsCheck else { return }
        showsCheck = true
        withAnimation(.easeOut(duration: 0.3)) { ringWidth = Self.diameter * 0.065 }
        withAnimation(.easeOut(duration: 0.35).delay(0.15)) { check = 1 }
    }
}

/// Coche de Face ID, proportions relevées sur l'animation d'origine (cadre = cercle extérieur).
private struct TouchIDCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: c.x - 0.367 * r, y: c.y + 0.033 * r))
        path.addLine(to: CGPoint(x: c.x - 0.08 * r, y: c.y + 0.367 * r))
        path.addLine(to: CGPoint(x: c.x + 0.367 * r, y: c.y - 0.28 * r))
        return path
    }
}

/// Vue d'une vidéo transparente : les images du lecteur sont posées une à une sur une couche ordinaire.
///
/// Pas d'AVPlayerLayer : un changement de bureau pendant la lecture décroche son affichage (la
/// lecture va jusqu'au bout, mais l'écran garde l'image du moment : Face ID figé sur le cercle, sans
/// la coche), et rien ne le raccroche de façon fiable. Les couches ordinaires, elles, continuent de
/// s'afficher : à chaque rafraîchissement de l'écran, on y pose l'image courante de la vidéo.
final class VideoHostView: NSView {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let frameLayer = CALayer()
    private var displayLink: CADisplayLink?
    #if DEBUG
    /// Diagnostic des bureaux : images posées, dernière image (temps de la vidéo), plus longue pause
    /// entre deux rafraîchissements de l'écran.
    private var framesShown = 0
    private var lastFrameTime = 0.0
    private var lastTick: CFTimeInterval = 0
    private var longestGap: CFTimeInterval = 0
    #endif

    init(player: AVPlayer) {
        self.player = player
        // Images BGRA avec transparence, sur IOSurface : posées telles quelles dans la couche.
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: NSDictionary(),
        ])
        super.init(frame: .zero)
        wantsLayer = true
        frameLayer.contentsGravity = .resizeAspect
        frameLayer.isOpaque = false
        frameLayer.frame = bounds
        frameLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Pas d'animation implicite d'une image à l'autre.
        frameLayer.actions = ["contents": NSNull()]
        layer?.addSublayer(frameLayer)
        player.currentItem?.add(output)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas utilisé")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(nextFrame))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Fin de l'affichage : lecture arrêtée, plus de rafraîchissement.
    func stop() {
        #if DEBUG
        if AutomatedRun.isDiagnostic {
            let line = String(format: "DEMO-DIAG vidéo : %d images posées · dernière à %.2f s · lecture à %.2f s · plus longue pause %.2f s\n",
                              framesShown, lastFrameTime, player.currentTime().seconds, longestGap)
            FileHandle.standardError.write(Data(line.utf8))
        }
        #endif
        player.pause()
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func nextFrame() {
        #if DEBUG
        let now = CACurrentMediaTime()
        if lastTick > 0 { longestGap = max(longestGap, now - lastTick) }
        lastTick = now
        #endif
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        frameLayer.contentsScale = window?.backingScaleFactor ?? 2
        frameLayer.contents = buffer
        #if DEBUG
        framesShown += 1
        lastFrameTime = time.seconds
        #endif
    }
}

/// Vidéo transparente jouée jusqu'à `holdAt`, en pause tant que `released` est faux, puis jusqu'au
/// bout (`onEnd`). `stillOnly` : image fixe à `holdAt`, sans lecture.
private struct StagedVideo: NSViewRepresentable {
    let resource: String
    let holdAt: Double
    let released: Bool
    var stillOnly = false
    let onEnd: () -> Void

    @MainActor
    final class Coordinator {
        var player: AVPlayer?
        var timeObservers: [Any] = []
        var endObserver: NSObjectProtocol?
        var released = false
        var onEnd: () -> Void = {}
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mov") else { return NSView() }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let view = VideoHostView(player: player)
        let coordinator = context.coordinator
        coordinator.player = player
        coordinator.onEnd = onEnd
        coordinator.released = released
        let hold = CMTime(seconds: holdAt, preferredTimescale: 600)
        if stillOnly {
            player.seek(to: hold, toleranceBefore: .zero, toleranceAfter: .zero)
            return view
        }
        coordinator.timeObservers.append(player.addBoundaryTimeObserver(forTimes: [NSValue(time: hold)], queue: .main) {
            MainActor.assumeIsolated { if !coordinator.released { player.pause() } }
        })
        coordinator.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in
            MainActor.assumeIsolated { coordinator.onEnd() }
        }
        player.play()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEnd = onEnd
        guard released, !coordinator.released else { return }
        coordinator.released = true
        if !stillOnly { coordinator.player?.play() }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        (view as? VideoHostView)?.stop()
        coordinator.player?.pause()
        coordinator.timeObservers.forEach { coordinator.player?.removeTimeObserver($0) }
        coordinator.timeObservers.removeAll()
        if let endObserver = coordinator.endObserver { NotificationCenter.default.removeObserver(endObserver) }
        coordinator.endObserver = nil
    }
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
            Toggle("Animation Face ID au déverrouillage du Mac", isOn: $module.animateUnlock)
            Toggle("Animation pendant une demande Touch ID", isOn: $module.animateTouchID)
            Toggle("Animation pendant une demande de mot de passe", isOn: $module.animatePassword)
            Text("Animations visuelles uniquement : Notchkit ne lit pas votre empreinte. macOS n'indique pas comment la session a été déverrouillée et rien ne peut s'afficher sur l'écran verrouillé : l'animation Touch ID se joue juste après le déverrouillage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
