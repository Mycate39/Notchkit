import AppKit
import SwiftUI

// Éléments de style communs de l'encoche, inspirés des principes de conception d'Apple :
// réponse immédiate à l'appui, profondeur par les matières, apparitions « matérielles ».

// MARK: - Boutons

/// Bouton de l'encoche : il s'enfonce dès l'appui (pas au relâchement) et revient avec un ressort.
struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            // Enfoncement quasi instantané ; retour en ressort sans rebond.
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NotchPressStyle {
    /// Style des boutons dans l'encoche.
    static var notch: NotchPressStyle { NotchPressStyle() }
}

// MARK: - Cartes

/// Surface d'une carte : fond discret et liseré plus clair en haut (la lumière accroche le bord),
/// renforcé quand « Augmenter le contraste » est activé dans macOS.
struct NotchCardSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let high = contrast == .increased
        content
            .background(.white.opacity(high ? 0.12 : 0.065), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(high ? 0.4 : 0.14), .white.opacity(high ? 0.25 : 0.03)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: high ? 1 : 0.5
                )
            }
    }
}

extension View {
    func notchCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(NotchCardSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Apparitions

/// Flou appliqué pendant une transition (le contenu se « matérialise » au lieu d'un simple fondu).
private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Apparition depuis l'encoche : léger agrandissement ancré en haut, flou qui se dissipe et fondu.
    /// Même chemin à l'aller et au retour.
    static var materialize: AnyTransition {
        .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.96, anchor: .top))
    }
}

// MARK: - Accessibilité

enum NotchAccessibility {
    /// « Réduire la transparence » (Réglages Système > Accessibilité > Affichage).
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
