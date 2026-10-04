import AppKit
import SwiftUI

/// Étoile animée représentant Claude dans l'encoche (création originale, pas le logo officiel).
///
/// Des rayons arrondis qui pulsent l'un après l'autre et tournent lentement quand Claude travaille.
/// Animée avec Core Animation : l'animation tourne dans le serveur d'affichage, sans réveiller l'app.
struct ClaudeSparkView: NSViewRepresentable {
    var isAnimating: Bool

    /// Orange chaud, proche des couleurs de Claude.
    static let color = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)

    func makeNSView(context: Context) -> ClaudeSparkNSView {
        ClaudeSparkNSView()
    }

    func updateNSView(_ view: ClaudeSparkNSView, context: Context) {
        view.setAnimating(isAnimating)
    }
}

final class ClaudeSparkNSView: NSView {
    private static let rayCount = 10
    private let container = CALayer()
    /// Chaque rayon est dans un support tourné, pour animer son échelle indépendamment de son angle.
    private var rays: [CALayer] = []
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(container)

        for index in 0..<Self.rayCount {
            let holder = CALayer()
            let ray = CALayer()
            ray.backgroundColor = ClaudeSparkView.color.cgColor
            ray.anchorPoint = CGPoint(x: 0.5, y: 0)
            holder.addSublayer(ray)
            holder.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(index) / CGFloat(Self.rayCount) * 2 * .pi))
            container.addSublayer(holder)
            rays.append(ray)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas utilisé")
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        for (index, ray) in rays.enumerated() {
            guard let holder = ray.superlayer else { continue }
            holder.bounds = bounds
            holder.position = center
            // Rayons alternativement longs et courts.
            let length = side * (index.isMultiple(of: 2) ? 0.5 : 0.38)
            let width = side * 0.13
            ray.bounds = CGRect(x: 0, y: 0, width: width, height: length)
            ray.position = CGPoint(x: bounds.midX, y: bounds.midY)
            ray.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    func setAnimating(_ animating: Bool) {
        guard animating != isAnimating else { return }
        isAnimating = animating

        if animating {
            for (index, ray) in rays.enumerated() {
                let pulse = CABasicAnimation(keyPath: "transform.scale.y")
                pulse.fromValue = 0.45
                pulse.toValue = 1.0
                pulse.duration = 0.7
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Décalage : la pulsation fait le tour de l'étoile.
                pulse.timeOffset = Double(index) / Double(Self.rayCount) * 1.4
                ray.add(pulse, forKey: "pulse")
            }
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = -2 * Double.pi
            rotation.duration = 9
            rotation.repeatCount = .infinity
            container.add(rotation, forKey: "rotation")
        } else {
            rays.forEach { $0.removeAnimation(forKey: "pulse") }
            container.removeAnimation(forKey: "rotation")
        }
    }
}
