import AppKit
import SwiftUI

/// Petit égaliseur animé (4 barres).
///
/// Animé avec Core Animation plutôt qu'avec SwiftUI : une fois lancées, les animations
/// sont exécutées par le serveur d'affichage de macOS, sans réveiller l'app à chaque image.
/// C'est nettement plus économe pour une animation qui tourne pendant toute une écoute.
struct EqualizerView: NSViewRepresentable {
    var isAnimating: Bool
    var color: NSColor = .white

    func makeNSView(context: Context) -> EqualizerNSView {
        EqualizerNSView()
    }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.barColor = color
        view.setAnimating(isAnimating)
    }
}

final class EqualizerNSView: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    /// Durées différentes pour que les barres ne bougent pas à l'unisson.
    private let durations: [CFTimeInterval] = [0.46, 0.62, 0.39, 0.54]
    private static let restingScale: CGFloat = 0.3
    private static let animationKey = "equalizer"

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
        let spacing = bounds.width * 0.12
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

    func setAnimating(_ animating: Bool) {
        for (index, bar) in bars.enumerated() {
            if animating {
                guard bar.animation(forKey: Self.animationKey) == nil else { continue }
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = Self.restingScale
                animation.toValue = 1.0
                animation.duration = durations[index]
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Décalage de phase entre les barres.
                animation.timeOffset = Double(index) * 0.17
                bar.add(animation, forKey: Self.animationKey)
            } else {
                bar.removeAnimation(forKey: Self.animationKey)
            }
        }
    }
}
