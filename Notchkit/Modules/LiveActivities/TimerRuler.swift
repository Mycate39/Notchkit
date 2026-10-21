import AppKit
import SwiftUI

/// Règle de durée façon minuteur d'iOS 26 : une graduation par minute, chiffres tous les 5,
/// partie choisie en orange, triangle au centre. Logique pure, testée.
enum TimerRulerMath {
    static let range: ClosedRange<Double> = 1...180
    /// Écart entre deux graduations (une minute).
    static let tickSpacing: CGFloat = 8

    /// Minutes après un déplacement des doigts (vers la gauche : la règle avance, la durée augmente).
    static func minutes(from start: Double, translation: CGFloat) -> Double {
        min(max(start - Double(translation / tickSpacing), range.lowerBound), range.upperBound)
    }

    /// Marge au bout de la règle (en minutes) : la graduation 0 et son chiffre restent lisibles.
    static let edgeInset: Double = 1.2

    /// Première minute visible à gauche (fonction pure, testée). La règle se centre sur la durée,
    /// mais bute à ses deux bouts comme une vraie règle : elle remplit toujours toute la largeur,
    /// et c'est alors le repère qui se déplace.
    static func windowStart(value: Double, visibleMinutes: Double) -> Double {
        let lowest = range.lowerBound - 1 - edgeInset
        let highest = range.upperBound + edgeInset - visibleMinutes
        return min(max(value - visibleMinutes / 2, lowest), max(lowest, highest))
    }

    /// Format le plus large, dont la place est toujours réservée, et tailles de police essayées.
    static let widestLabel = "0:00:00"
    static let labelSizes: [CGFloat] = [38, 32, 27, 22]

    /// Durée affichée en grand : « 15:00 » ou « 1:15:00 ».
    static func label(minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d:%02d:00", minutes / 60, minutes % 60) : String(format: "%d:00", minutes)
    }
}

/// Réglage d'un minuteur avec la règle : défilement à deux doigts (ou glisser) sur la règle,
/// un cran haptique par minute, puis « Démarrer ».
struct TimerRulerSetupView: View {
    let module: LiveActivitiesModule
    /// Raccourcis secondaires (chronomètre, alarme…) affichés à côté de « Démarrer ».
    var extras: AnyView?

    @AppStorage("module.activities.rulerMinutes") private var storedMinutes = 15
    @State private var value: Double = 15
    @State private var gestureStart: Double?

    private var minutes: Int { Int(value.rounded()) }

    var body: some View {
        VStack(spacing: 6) {
            ruler
                .frame(height: 44)
                .overlay { HorizontalScrollCatcher(onChange: scroll, onEnd: settle) }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    module.startTimer(minutes: Double(minutes))
                } label: {
                    Text("Démarrer")
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize()
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.notch)
                .keyboardShortcut(.defaultAction)
                extras
                Spacer(minLength: 4)
                // Taille fixe, choisie pour que le format le plus long (« 3:00:00 ») tienne : passer
                // d'une durée en minutes à une durée en heures ne change ni la police ni la disposition.
                ViewThatFits(in: .horizontal) {
                    ForEach(TimerRulerMath.labelSizes, id: \.self) { size in
                        durationLabel(size: size)
                    }
                }
            }
        }
        .onAppear { value = Double(storedMinutes) }
    }

    private func durationLabel(size: CGFloat) -> some View {
        let font = Font.system(size: size, weight: .light).monospacedDigit()
        return ZStack(alignment: .trailing) {
            Text(verbatim: TimerRulerMath.widestLabel).font(font).hidden()
            Text(TimerRulerMath.label(minutes: minutes))
                .font(font)
                .foregroundStyle(.orange)
                .contentTransition(.numericText(value: Double(minutes)))
                .animation(.snappy(duration: 0.2), value: minutes)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var ruler: some View {
        Canvas { context, size in
            let spacing = TimerRulerMath.tickSpacing
            let visible = Double(size.width / spacing)
            let start = TimerRulerMath.windowStart(value: value, visibleMinutes: visible)
            let fadeWidth = size.width * 0.18
            // Les graduations s'estompent vers un bord seulement si la règle continue au-delà.
            let moreLeft = start > TimerRulerMath.range.lowerBound - 1 - TimerRulerMath.edgeInset + 0.01
            let moreRight = start + visible < TimerRulerMath.range.upperBound + TimerRulerMath.edgeInset - 0.01
            let tickTop: CGFloat = 18
            let first = max(0, Int(start.rounded(.down)))
            let last = min(Int(TimerRulerMath.range.upperBound), Int((start + visible).rounded(.up)))
            for minute in first...max(first, last) {
                let x = CGFloat(Double(minute) - start) * spacing
                var fade = 1.0
                if moreLeft { fade = min(fade, Double(x / fadeWidth)) }
                if moreRight { fade = min(fade, Double((size.width - x) / fadeWidth)) }
                guard fade > 0 else { continue }
                let chosen = Double(minute) <= value + 0.001
                let color = Color.orange.opacity((chosen ? 1 : 0.35) * fade)
                let tick = Path(roundedRect: CGRect(x: x - 1, y: tickTop, width: 2, height: size.height - tickTop - 10),
                                cornerRadius: 1)
                context.fill(tick, with: .color(color))
                if minute % 5 == 0 {
                    let text = Text(verbatim: "\(minute)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
                    context.draw(text, at: CGPoint(x: x, y: 7))
                }
            }
            // Repère sous la durée choisie : triangle aux coins arrondis (tracé épais à jointures rondes).
            let marker = CGFloat(value - start) * spacing
            let corner: CGFloat = 1.2
            var triangle = Path()
            triangle.move(to: CGPoint(x: marker, y: size.height - 8 + corner))
            triangle.addLine(to: CGPoint(x: marker + 5.5 - corner, y: size.height - corner))
            triangle.addLine(to: CGPoint(x: marker - 5.5 + corner, y: size.height - corner))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(.orange))
            context.stroke(triangle, with: .color(.orange), style: StrokeStyle(lineWidth: corner * 2, lineJoin: .round))
        }
    }

    private func scroll(_ translation: CGFloat) {
        let start = gestureStart ?? value
        gestureStart = start
        let previous = minutes
        value = TimerRulerMath.minutes(from: start, translation: translation)
        guard minutes != previous else { return }
        // Cran par minute ; « alignement » quand la règle bute à l'un de ses bouts.
        let atEnd = Double(minutes) == TimerRulerMath.range.lowerBound || Double(minutes) == TimerRulerMath.range.upperBound
        Haptics.play(atEnd ? .snap : .step)
    }

    /// Fin du geste (inertie comprise) : la règle se cale sur la minute la plus proche.
    private func settle() {
        gestureStart = nil
        withAnimation(.snappy(duration: 0.2)) { value = value.rounded() }
        storedMinutes = minutes
    }
}

/// Reçoit le défilement horizontal (trackpad, molette) et le glisser à la souris au-dessus d'une vue,
/// à la place du balayage des pages de l'encoche (`PageSwiper` lui laisse ces gestes).
struct HorizontalScrollCatcher: NSViewRepresentable {
    /// Déplacement cumulé depuis le début du geste (positif : vers la droite).
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: ScrollCatcherView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }
}

final class ScrollCatcherView: NSView {
    var onChange: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var translation: CGFloat = 0
    private var dragStartX: CGFloat?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Un geste à deux doigts commencé sur la règle est en cours (inertie comprise).
    private var isTracking = false
    /// Fin du geste différée : l'inertie du trackpad commence juste après le relâchement.
    private var pendingEnd: DispatchWorkItem?

    override func scrollWheel(with event: NSEvent) {
        // Molette de souris : chaque cran fait avancer d'une minute.
        guard !event.phase.isEmpty || !event.momentumPhase.isEmpty else {
            onChange?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : TimerRulerMath.tickSpacing))
            onEnd?()
            return
        }
        if event.phase.contains(.began) {
            pendingEnd?.cancel()
            translation = 0
            isTracking = true
        }
        // Défilement cinétique : la règle continue sur sa lancée après le relâchement.
        if event.momentumPhase.contains(.began) { pendingEnd?.cancel() }
        guard isTracking else { return }
        translation += abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        onChange?(translation)
        if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            finish()
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            // Sans inertie (doigts arrêtés avant de se lever), aucun événement ne suit : on termine.
            let end = DispatchWorkItem { [weak self] in self?.finish() }
            pendingEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: end)
        }
    }

    private func finish() {
        pendingEnd?.cancel()
        pendingEnd = nil
        guard isTracking else { return }
        isTracking = false
        translation = 0
        onEnd?()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = convert(event.locationInWindow, from: nil).x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        onChange?(convert(event.locationInWindow, from: nil).x - dragStartX)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartX = nil
        onEnd?()
    }
}
