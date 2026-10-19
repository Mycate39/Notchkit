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
    /// Pilule au repos : gris très sombre sur le noir. Blanc translucide plutôt qu'un gris opaque :
    /// identique sur fond noir, mais il laisse transparaître le Liquid Glass au lieu de faire tache.
    static let surface = Color.white.opacity(0.15)
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
    @State private var isHovering = false

    /// Bouton rond secondaire (« + », « × », réglages…) : le symbole seul, sans fond ni contour.
    private var isBare: Bool { isCircle && !isActive }

    var body: some View {
        let pressed = configuration.isPressed
        let shape: AnyShape = isCircle ? AnyShape(Circle()) : AnyShape(Capsule())
        configuration.label
            .font(.system(size: isBare ? size.fontSize + 3 : size.fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(isActive ? AnyShapeStyle(StandBy.onAccent)
                                      : AnyShapeStyle(.white.opacity(isBare && !isHovering ? 0.8 : 1)))
            .padding(.horizontal, isCircle ? 0 : size.horizontalPadding)
            .frame(width: isCircle ? size.height : nil, height: size.height)
            .background {
                if isActive {
                    shape.fill(.tint)
                } else if !isBare {
                    shape.fill(StandBy.surface)
                }
            }
            // Liseré clair en haut : la pilule paraît légèrement bombée.
            .overlay {
                if !isBare {
                    shape.stroke(
                        LinearGradient(colors: [.white.opacity(isActive ? 0.25 : 0.1), .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
                }
            }
            .onHover { isHovering = $0 }
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

/// Couleur du remplissage des curseurs (`nil` = couleur d'accent).
private struct SliderTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var sliderTint: Color? {
        get { self[SliderTintKey.self] }
        set { self[SliderTintKey.self] = newValue }
    }
}

/// Curseur façon iOS 26 : rail fin, remplissage coloré jusqu'à une pastille blanche toujours visible,
/// qui grossit et devient une loupe de verre pendant le glissement (Liquid Glass sur macOS 26).
/// `height` est la hauteur occupée ; la zone cliquable fait au moins `NotchLayout.sliderMinimumHitHeight`.
struct StandBySlider: View {
    @Binding var value: Double
    var height: CGFloat = 26
    var onChange: (Double) -> Void = { _ in }

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    var body: some View {
        let hitHeight = NotchLayout.sliderHitHeight(for: height)
        let knob = NotchLayout.sliderKnobSize(for: height, isDragging: false)
        GeometryReader { proxy in
            SliderTrack(value: value, height: height, width: proxy.size.width, isDragging: isDragging)
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            set(NotchLayout.sliderFraction(atX: drag.location.x, trackWidth: proxy.size.width, knobWidth: knob.width))
                        }
                        .onEnded { _ in isDragging = false }
                )
        }
        .frame(height: hitHeight)
        // Zone cliquable agrandie, encombrement inchangé.
        .padding(.vertical, -(hitHeight - height) / 2)
        .animation(.spring(duration: 0.3, bounce: 0.25), value: isDragging)
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
        guard clamped != value else { return }
        // Butée : petit « clic » du trackpad en atteignant le minimum ou le maximum.
        if clamped == 0 || clamped == 1 { Haptics.play(.snap) }
        value = clamped
        onChange(clamped)
    }
}

/// Rail du curseur : fin, remplissage coloré jusqu'au centre de la pastille.
struct SliderTrack: View {
    var value: Double
    var height: CGFloat
    var width: CGFloat
    var isDragging: Bool

    @Environment(\.sliderTint) private var sliderTint

    var body: some View {
        let fraction = min(max(value, 0), 1)
        let thickness = NotchLayout.sliderTrackThickness(for: height)
        let rest = NotchLayout.sliderKnobSize(for: height, isDragging: false)
        let knob = NotchLayout.sliderKnobSize(for: height, isDragging: isDragging)
        let center = NotchLayout.sliderKnobCenter(fraction: fraction, trackWidth: width, knobWidth: rest.width)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(height: thickness)
            Capsule()
                .fill(sliderTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
                .frame(width: max(thickness, center), height: thickness)
            SliderKnob(isDragging: isDragging)
                .frame(width: knob.width, height: knob.height)
                .offset(x: center - knob.width / 2)
        }
        .frame(width: width, height: height)
    }
}

/// Pastille : blanche au repos, loupe de verre transparente pendant le glissement.
private struct SliderKnob: View {
    var isDragging: Bool

    var body: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.white.opacity(isDragging ? 0.06 : 1))
                .glassEffect(isDragging ? .clear.interactive() : .regular.interactive(), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: isDragging ? 6 : 3, y: 1)
        } else {
            Capsule()
                .fill(.white.opacity(isDragging ? 0.18 : 1))
                .overlay(Capsule().strokeBorder(.white.opacity(isDragging ? 0.8 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: isDragging ? 6 : 3, y: 1)
        }
    }
}

// MARK: - Cartes

/// Surface d'une carte : fond noir opaque et sans bordure, comme les Live Activities de l'iPhone.
/// Seul « Augmenter le contraste » (Réglages Système > Accessibilité) ajoute un liseré pour
/// distinguer les cartes de l'encoche.
struct NotchCardSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.black, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(.white.opacity(0.4), lineWidth: 1)
                }
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
    /// Apparition depuis l'encoche : flou qui se dissipe et fondu, la forme qui grandit donnant
    /// l'élan. Même chemin à l'aller et au retour. Pas d'agrandissement : sur les vues AppKit (pages
    /// défilantes), SwiftUI redimensionne réellement le cadre à chaque image, le défilement dérive
    /// de quelques points puis se recale d'un coup à la fin de l'animation.
    static var materialize: AnyTransition {
        .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
    }
}

// MARK: - Accessibilité

enum NotchAccessibility {
    /// « Réduire la transparence » (Réglages Système > Accessibilité > Affichage).
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
