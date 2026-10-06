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

// MARK: - Style StandBy

/// Palette inspirée du mode Nuit de StandBy (iPhone) : noir OLED, pilules gris très sombre,
/// ambre chaleureux pour ce qui est actif (bouton principal, progression, onglet choisi).
enum StandBy {
    /// Ambre par défaut des états actifs (remplaçable par la couleur d'accent des réglages).
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.16)
    /// Pilule au repos : gris très sombre, à peine détaché du noir.
    static let surface = Color(white: 0.15)
    /// Texte et symboles posés sur l'ambre : noir chaud, lisible sans éblouir.
    static let onAccent = Color(red: 0.12, green: 0.07, blue: 0.0)
}

/// Bouton StandBy : pilule (ou cercle) épaisse et tactile.
/// Au repos, gris sombre et texte blanc ; actif, rempli d'ambre (la teinte) avec texte noir.
/// S'enfonce dès l'appui et s'éclaire légèrement, puis revient avec un ressort.
struct StandByButtonStyle: ButtonStyle {
    enum Size {
        case small, regular, large

        /// Hauteur de la pilule (diamètre pour un cercle).
        var height: CGFloat {
            switch self {
            case .small: 22
            case .regular: 30
            case .large: 42
            }
        }
        var fontSize: CGFloat {
            switch self {
            case .small: 10
            case .regular: 12
            case .large: 17
            }
        }
        var horizontalPadding: CGFloat {
            switch self {
            case .small: 9
            case .regular: 13
            case .large: 18
            }
        }
    }

    var size: Size = .regular
    var isActive = false
    var isCircle = false

    func makeBody(configuration: Configuration) -> some View {
        StandByButtonBody(configuration: configuration, size: size, isActive: isActive, isCircle: isCircle)
    }
}

private struct StandByButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: StandByButtonStyle.Size
    let isActive: Bool
    let isCircle: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        let shape: AnyShape = isCircle ? AnyShape(Circle()) : AnyShape(Capsule())
        configuration.label
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(isActive ? AnyShapeStyle(StandBy.onAccent) : AnyShapeStyle(.white))
            .padding(.horizontal, isCircle ? 0 : size.horizontalPadding)
            .frame(width: isCircle ? size.height : nil, height: size.height)
            .background {
                if isActive {
                    shape.fill(.tint)
                } else {
                    shape.fill(StandBy.surface)
                }
            }
            // Liseré clair en haut : la pilule paraît légèrement bombée.
            .overlay {
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(isActive ? 0.25 : 0.1), .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5
                )
            }
            .contentShape(shape)
            .brightness(pressed ? (isActive ? -0.1 : 0.08) : 0)
            .scaleEffect(pressed ? 0.93 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(pressed ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0.2), value: pressed)
    }
}

extension ButtonStyle where Self == StandByButtonStyle {
    /// Pilule StandBy ; `active` la remplit d'ambre, `circle` en fait un bouton rond.
    static func standBy(_ size: StandByButtonStyle.Size = .regular, active: Bool = false,
                        circle: Bool = false) -> StandByButtonStyle {
        StandByButtonStyle(size: size, isActive: active, isCircle: circle)
    }
}

/// Barre de progression StandBy : épaisse, piste gris sombre, remplissage ambre.
struct StandByBar: View {
    var value: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(StandBy.surface)
                Capsule().fill(.tint)
                    // Jamais plus étroite qu'un cercle, pour garder des bouts arrondis.
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * fraction) : 0)
            }
        }
        .frame(height: height)
    }
}

/// Curseur StandBy : une pilule épaisse qu'on remplit en glissant (sans bouton rond),
/// comme les curseurs du centre de contrôle de l'iPhone.
struct StandBySlider: View {
    @Binding var value: Double
    var height: CGFloat = 26
    var onChange: (Double) -> Void = { _ in }

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            StandByBar(value: value, height: height)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            set(drag.location.x / max(1, proxy.size.width))
                        }
                        .onEnded { _ in isDragging = false }
                )
        }
        .frame(height: height)
        .scaleEffect(y: isDragging ? 1.08 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isDragging)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 1.0 / 16)
            case .decrement: set(value - 1.0 / 16)
            @unknown default: break
            }
        }
    }

    private func set(_ newValue: Double) {
        let clamped = min(max(newValue, 0), 1)
        value = clamped
        onChange(clamped)
    }
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
