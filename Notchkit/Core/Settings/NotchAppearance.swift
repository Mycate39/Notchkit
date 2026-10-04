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
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .compact: "Compacte"
            case .standard: "Standard"
            case .large: "Grande"
            }
        }

        /// Taille de l'encoche dépliée.
        var expandedSize: CGSize {
            switch self {
            case .compact: CGSize(width: 560, height: 176)
            case .standard: CGSize(width: 640, height: 190)
            case .large: CGSize(width: 760, height: 214)
            }
        }

        /// Largeur d'une page, en tailles de widget (Petit = 1).
        var pageCapacity: CGFloat {
            switch self {
            case .compact: 3.5
            case .standard: 4
            case .large: 5
            }
        }
    }

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
            case .fluid: (0.38, 0.18)
            case .quick: (0.24, 0.04)
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
    var animation: AnimationStyle = .fluid
    var background: Background = .black
    var customBackground = StoredColor(red: 0.1, green: 0.1, blue: 0.18)
    /// Couleur d'accent (onglets, liens, curseurs) ; `nil` = couleur du système.
    var accent: StoredColor?

    init() {}

    // Décodage tolérant (nouveaux réglages ajoutés plus tard).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotchAppearance()
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? d.size
        animation = (try? c.decodeIfPresent(AnimationStyle.self, forKey: .animation)) ?? d.animation
        background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? d.background
        customBackground = (try? c.decodeIfPresent(StoredColor.self, forKey: .customBackground)) ?? d.customBackground
        accent = try? c.decodeIfPresent(StoredColor.self, forKey: .accent)
    }

    /// Couleur d'accent effective.
    var accentColor: Color { accent?.color ?? .accentColor }
}

/// Fond de l'encoche selon l'apparence.
struct NotchBackground: View {
    let appearance: NotchAppearance

    var body: some View {
        switch appearance.background {
        case .black: Color.black
        case .graphite: Color(white: 0.13)
        case .glass: Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        case .custom: appearance.customBackground.color
        }
    }
}
