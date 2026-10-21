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
                Text(TimerRulerMath.label(minutes: minutes))
                    .font(.system(size: 38, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .animation(.snappy(duration: 0.2), value: minutes)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .onAppear { value = Double(storedMinutes) }
    }

    private var ruler: some View {
        Canvas { context, size in
            let center = size.width / 2
            let tickTop: CGFloat = 18
            let first = Int((value - Double(center / TimerRulerMath.tickSpacing)).rounded(.down)) - 1
            let last = Int((value + Double(center / TimerRulerMath.tickSpacing)).rounded(.up)) + 1
            for minute in max(0, first)...max(0, last) where Double(minute) <= TimerRulerMath.range.upperBound {
                let x = center + CGFloat(Double(minute) - value) * TimerRulerMath.tickSpacing
                let chosen = Double(minute) <= value + 0.001
                let color = Color.orange.opacity(chosen ? 1 : 0.35)
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
            // Repère central : triangle aux coins arrondis (tracé épais à jointures rondes).
            let corner: CGFloat = 1.2
            var triangle = Path()
            triangle.move(to: CGPoint(x: center, y: size.height - 8 + corner))
            triangle.addLine(to: CGPoint(x: center + 5.5 - corner, y: size.height - corner))
            triangle.addLine(to: CGPoint(x: center - 5.5 + corner, y: size.height - corner))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(.orange))
            context.stroke(triangle, with: .color(.orange), style: StrokeStyle(lineWidth: corner * 2, lineJoin: .round))
        }
        // Graduations qui s'estompent vers les bords.
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.18),
            .init(color: .black, location: 0.82),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing))
    }

    private func scroll(_ translation: CGFloat) {
        let start = gestureStart ?? value
        gestureStart = start
        let previous = minutes
        value = TimerRulerMath.minutes(from: start, translation: translation)
        if minutes != previous { Haptics.play(.step) }
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

    override func scrollWheel(with event: NSEvent) {
        // Pas d'inertie : la règle s'arrête sous les doigts, puis se cale.
        guard event.momentumPhase.isEmpty else { return }
        // Molette de souris : chaque cran fait avancer d'une minute.
        guard !event.phase.isEmpty else {
            onChange?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : TimerRulerMath.tickSpacing))
            onEnd?()
            return
        }
        if event.phase.contains(.began) { translation = 0 }
        translation += abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        onChange?(translation)
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            translation = 0
            onEnd?()
        }
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
