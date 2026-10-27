import AppKit
import SwiftUI

/// Couleur enregistrable (composantes sRGB).
struct StoredColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, opacity: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }
}

/// Apparence de l'encoche choisie dans les réglages (onglet « Apparence »).
struct NotchAppearance: Codable, Equatable, Sendable {
    enum AnimationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case fluid, quick, bouncy, none
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .fluid: "Fluide"
            case .quick: "Rapide"
            case .bouncy: "Rebondissante"
            case .none: "Aucune"
            }
        }

        /// Durée et rebond du ressort.
        var spring: (duration: Double, bounce: Double) {
            switch self {
            // Sans rebond : l'ouverture au survol n'a pas d'élan à prolonger (principes d'Apple :
            // amortissement critique par défaut, rebond réservé aux gestes lancés).
            case .fluid: (0.36, 0)
            case .quick: (0.24, 0)
            case .bouncy: (0.5, 0.38)
            case .none: (0.01, 0)
            }
        }
    }

    /// Fond de l'encoche : noir ou verre (les fonds Graphite et Personnalisé des versions précédentes
    /// ne se décodent plus et repassent au noir).
    enum Background: String, Codable, CaseIterable, Identifiable, Sendable {
        case black, glass
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .black: "Noir"
            case .glass: "Verre"
            }
        }
    }

    var animation: AnimationStyle = .fluid
    var background: Background = .black
    /// Couleur d'accent (onglets, liens, curseurs) ; `nil` = ambre du style StandBy.
    var accent: StoredColor?
    /// Couleur du remplissage des curseurs ; `nil` = couleur d'accent.
    var sliderColor: StoredColor?

    init() {}

    // Décodage tolérant (nouveaux réglages ajoutés plus tard ; la taille d'encoche des anciennes versions,
    // remplacée par une taille qui suit les widgets, est ignorée).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotchAppearance()
        animation = (try? c.decodeIfPresent(AnimationStyle.self, forKey: .animation)) ?? d.animation
        background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? d.background
        accent = try? c.decodeIfPresent(StoredColor.self, forKey: .accent)
        sliderColor = try? c.decodeIfPresent(StoredColor.self, forKey: .sliderColor)
    }

    /// Couleur d'accent effective.
    var accentColor: Color { (accent ?? StandBy.defaultAccent).color }
    /// Texte posé sur la couleur d'accent.
    var onAccentColor: Color { StandBy.onAccent(for: accent ?? StandBy.defaultAccent) }
}

extension View {
    /// Fond de l'encoche. En mode encoche (réelle ou simulée), il reste noir pour se fondre avec la
    /// découpe de l'écran ; avec « Verre », l'encoche ouverte (`glassRevealed`) passe au verre sous la
    /// hauteur de l'encoche matérielle (`notchHeight`). « Verre » utilise le Liquid Glass de macOS 26.
    @ViewBuilder
    func notchBackground(_ appearance: NotchAppearance, style: NotchStyle, shape: some Shape,
                         notchHeight: CGFloat = 0, glassRevealed: Bool = false) -> some View {
        if style == .notch {
            if appearance.usesGlassWidgets {
                background(GlassNotchBackground(notchHeight: notchHeight, revealed: glassRevealed, shape: AnyShape(shape)))
            } else {
                background(Color.black)
            }
        } else if appearance.background == .glass, !NotchAccessibility.reduceTransparency {
            if #available(macOS 26.0, *) {
                // Verre liquide : réfraction et reflets sur les bords, légèrement teinté pour la lisibilité.
                glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)
            } else {
                background(NotchBackground(appearance: appearance))
            }
        } else {
            background(NotchBackground(appearance: appearance))
        }
    }
}

extension NotchAppearance {
    /// Fond « Verre » : widgets posés directement sur le verre, sans carte (sauf « Réduire la transparence »).
    @MainActor var usesGlassWidgets: Bool {
        background == .glass && !NotchAccessibility.reduceTransparency
    }
}

/// Fond « Verre » d'une vraie encoche, façon lecteur de l'iPhone : noir plein sur le haut (la découpe
/// de l'écran reste invisible), long dégradé, puis verre clair, sans contour. Repliée,
/// l'encoche est entièrement noire ; le verre se dévoile avec le ressort de l'ouverture.
struct GlassNotchBackground: View {
    let notchHeight: CGFloat
    let revealed: Bool
    let shape: AnyShape

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let fadeStart = min(1, max(notchHeight / height, NotchLayout.glassBlackFraction))
            ZStack {
                glass
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: fadeStart),
                    .init(color: .black.opacity(NotchLayout.glassBottomDarkness), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                Color.black.opacity(revealed ? 0 : 1)
            }
            .animation(NotchLayout.spring, value: revealed)
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            // Verre clair : le fond d'écran reste net derrière, seulement réfracté sur les bords.
            Color.clear.glassEffect(.clear.tint(.black.opacity(NotchLayout.glassTint)), in: shape)
        } else {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(NotchLayout.glassTint))
                .environment(\.colorScheme, .dark)
        }
    }
}

/// Fond de l'encoche selon l'apparence.
struct NotchBackground: View {
    let appearance: NotchAppearance

    var body: some View {
        switch appearance.background {
        case .black: Color.black
        case .glass:
            if NotchAccessibility.reduceTransparency {
                // « Réduire la transparence » : verre remplacé par une surface opaque.
                Color(white: 0.12)
            } else {
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            }
        }
    }
}
