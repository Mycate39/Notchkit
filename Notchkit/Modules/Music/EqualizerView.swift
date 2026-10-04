import AppKit
import SwiftUI

/// Petit égaliseur animé (7 barres fines).
///
/// Animé avec Core Animation plutôt qu'avec SwiftUI : une fois lancées, les animations
/// sont exécutées par le serveur d'affichage de macOS, sans réveiller l'app à chaque image.
/// C'est nettement plus économe pour une animation qui tourne pendant toute une écoute.
///
/// Avec un `monitor`, les barres suivent le son en temps réel ; sans données en direct
/// (capture arrêtée, silence, autorisation refusée), elles reprennent l'animation simple.
struct EqualizerView: NSViewRepresentable {
    var isAnimating: Bool
    var monitor: AudioSpectrumMonitor?
    var color: NSColor = .white

    func makeNSView(context: Context) -> EqualizerNSView {
        EqualizerNSView()
    }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.barColor = color
        view.attach(to: monitor)
        view.setAnimating(isAnimating)
    }

    static func dismantleNSView(_ view: EqualizerNSView, coordinator: ()) {
        view.attach(to: nil)
    }
}

final class EqualizerNSView: NSView {
    private let bars: [CALayer] = (0..<SpectrumAnalyzer.defaultBandCount).map { _ in CALayer() }
    /// Durées différentes pour que les barres ne bougent pas à l'unisson (animation simple).
    private let durations: [CFTimeInterval] = [0.46, 0.62, 0.39, 0.54, 0.43, 0.58, 0.36]
    private static let restingScale: CGFloat = 0.3
    private static let animationKey = "equalizer"

    private weak var monitor: AudioSpectrumMonitor?
    private var subscription: UUID?
    private var isAnimating = false
    /// Vrai tant que des niveaux en direct arrivent.
    private var isLive = false

    var barColor: NSColor = .white {
        didSet { bars.forEach { $0.backgroundColor = barColor.cgColor } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for bar in bars {
            bar.backgroundColor = barColor.cgColor
            // Les barres grandissent depuis le bas.
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.transform = CATransform3DMakeScale(1, Self.restingScale, 1)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas utilisé")
    }

    override func layout() {
        super.layout()
        let count = CGFloat(bars.count)
        let spacing = bounds.width * 0.07
        let width = (bounds.width - spacing * (count - 1)) / count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: 0)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    /// S'abonne (ou se désabonne) aux niveaux en direct.
    func attach(to newMonitor: AudioSpectrumMonitor?) {
        guard newMonitor !== monitor else { return }
        if let subscription { monitor?.unsubscribe(subscription) }
        subscription = nil
        monitor = newMonitor
        subscription = newMonitor?.subscribe { [weak self] levels in
            self?.apply(levels)
        }
        if newMonitor == nil { apply(nil) }
    }

    /// Niveaux en direct (0…1 par barre) ; `nil` = retour à l'animation simple.
    private func apply(_ levels: [Float]?) {
        guard let levels, isAnimating else {
            if isLive {
                isLive = false
                startLoopAnimations(isAnimating)
            }
            return
        }
        if !isLive {
            isLive = true
            bars.forEach { $0.removeAnimation(forKey: Self.animationKey) }
        }
        // Très courte transition implicite entre deux mises à jour (≈ 60 par seconde).
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 60)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (index, bar) in bars.enumerated() {
            let level = CGFloat(index < levels.count ? levels[index] : 0)
            bar.transform = CATransform3DMakeScale(1, Self.restingScale + (1 - Self.restingScale) * level, 1)
        }
        CATransaction.commit()
    }

    func setAnimating(_ animating: Bool) {
        guard animating != isAnimating else { return }
        isAnimating = animating
        if !animating {
            isLive = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bars.forEach { $0.transform = CATransform3DMakeScale(1, Self.restingScale, 1) }
            CATransaction.commit()
        }
        if !isLive { startLoopAnimations(animating) }
    }

    private func startLoopAnimations(_ animating: Bool) {
        for (index, bar) in bars.enumerated() {
            if animating {
                guard bar.animation(forKey: Self.animationKey) == nil else { continue }
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = Self.restingScale
                animation.toValue = 1.0
                animation.duration = durations[index % durations.count]
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Décalage de phase entre les barres.
                animation.timeOffset = Double(index) * 0.11
                bar.add(animation, forKey: Self.animationKey)
            } else {
                bar.removeAnimation(forKey: Self.animationKey)
            }
        }
    }
}
