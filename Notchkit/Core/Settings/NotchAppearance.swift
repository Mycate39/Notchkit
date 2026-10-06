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
    enum Size: String, Codable, CaseIterable, Identifiable, Sendable {
        case compact, standard, large
        /// Taille libre, réglée avec des curseurs.
        case custom
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .compact: "Compacte"
            case .standard: "Standard"
            case .large: "Grande"
            case .custom: "Personnalisée"
            }
        }

        /// Taille de l'encoche dépliée (pour « Personnalisée », voir `NotchAppearance.expandedSize`).
        var expandedSize: CGSize {
            switch self {
            case .compact: CGSize(width: 560, height: 176)
            case .standard: CGSize(width: 640, height: 190)
            case .large: CGSize(width: 760, height: 214)
            case .custom: CGSize(width: 680, height: 200)
            }
        }

        /// Largeur d'une page, en tailles de widget (Petit = 1).
        var pageCapacity: CGFloat {
            switch self {
            case .compact: 3.5
            case .standard: 4
            case .large: 5
            case .custom: 4
            }
        }
    }

    /// Bornes des curseurs de taille personnalisée.
    static let customWidthRange: ClosedRange<Double> = 480...960
    static let customHeightRange: ClosedRange<Double> = 150...280

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

    enum Background: String, Codable, CaseIterable, Identifiable, Sendable {
        case black, graphite, glass, custom
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .black: "Noir"
            case .graphite: "Graphite"
            case .glass: "Verre"
            case .custom: "Personnalisé"
            }
        }
    }

    var size: Size = .standard
    var customWidth: Double = 680
    var customHeight: Double = 200
    var animation: AnimationStyle = .fluid
    var background: Background = .black
    var customBackground = StoredColor(red: 0.1, green: 0.1, blue: 0.18)
    /// Couleur d'accent (onglets, liens, curseurs) ; `nil` = ambre du style StandBy.
    var accent: StoredColor?

    init() {}

    // Décodage tolérant (nouveaux réglages ajoutés plus tard).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotchAppearance()
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? d.size
        customWidth = (try? c.decodeIfPresent(Double.self, forKey: .customWidth)) ?? d.customWidth
        customHeight = (try? c.decodeIfPresent(Double.self, forKey: .customHeight)) ?? d.customHeight
        animation = (try? c.decodeIfPresent(AnimationStyle.self, forKey: .animation)) ?? d.animation
        background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? d.background
        customBackground = (try? c.decodeIfPresent(StoredColor.self, forKey: .customBackground)) ?? d.customBackground
        accent = try? c.decodeIfPresent(StoredColor.self, forKey: .accent)
    }

    /// Taille effective de l'encoche dépliée.
    var expandedSize: CGSize {
        size == .custom ? CGSize(width: customWidth.rounded(), height: customHeight.rounded()) : size.expandedSize
    }

    /// Largeur d'une page (en tailles de widget) : proportionnelle à la largeur pour la taille libre.
    var pageCapacity: CGFloat {
        guard size == .custom else { return size.pageCapacity }
        return max(2.5, (CGFloat(customWidth) / 160 * 2).rounded(.down) / 2)
    }

    /// Couleur d'accent effective.
    var accentColor: Color { accent?.color ?? StandBy.amber }
}

extension View {
    /// Fond de l'encoche. En mode encoche (réelle ou simulée), il reste noir quoi qu'il arrive,
    /// pour se fondre avec la découpe de l'écran. « Verre » utilise le Liquid Glass de macOS 26.
    @ViewBuilder
    func notchBackground(_ appearance: NotchAppearance, style: NotchStyle, shape: some Shape) -> some View {
        if style == .notch {
            background(Color.black)
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

/// Fond de l'encoche selon l'apparence.
struct NotchBackground: View {
    let appearance: NotchAppearance

    var body: some View {
        switch appearance.background {
        case .black: Color.black
        case .graphite: Color(white: 0.13)
        case .glass:
            if NotchAccessibility.reduceTransparency {
                // « Réduire la transparence » : verre remplacé par une surface opaque.
                Color(white: 0.12)
            } else {
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            }
        case .custom: appearance.customBackground.color
        }
    }
}
