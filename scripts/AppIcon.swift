import AppKit
import SwiftUI

// Icône de Notchkit (grille macOS : toile 1024, corps 824, coins continus ~185).
let canvas: CGFloat = 1024
let body: CGFloat = 824
let radius: CGFloat = 185
let amber = Color(red: 1.0, green: 0.62, blue: 0.16)

struct Squircle<Fill: View>: View {
    @ViewBuilder var fill: Fill
    var body: some View {
        fill
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                // Liseré clair en haut : la lumière accroche le bord.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.0)],
                                                 startPoint: .top, endPoint: .center), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.35), radius: 28, y: 18)
            .frame(width: canvas, height: canvas)
    }
}

/// Barres de son en cloche.
struct Bars: View {
    var color: Color
    var height: CGFloat
    var body: some View {
        HStack(alignment: .center, spacing: height * 0.13) {
            ForEach([0.35, 0.6, 0.85, 1.0, 0.85, 0.6, 0.35], id: \.self) { h in
                Capsule().fill(color).frame(width: height * 0.12, height: height * h)
            }
        }
        .frame(height: height)
    }
}

/// Encoche collée en haut : congés concaves et bas arrondi.
struct NotchForm: Shape {
    var ear: CGFloat
    var bottom: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = r.minX + ear, rr = r.maxX - ear
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: l, y: r.minY + ear), control: CGPoint(x: l, y: r.minY))
        p.addLine(to: CGPoint(x: l, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: l + bottom, y: r.maxY), control: CGPoint(x: l, y: r.maxY))
        p.addLine(to: CGPoint(x: rr - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: rr, y: r.maxY - bottom), control: CGPoint(x: rr, y: r.maxY))
        p.addLine(to: CGPoint(x: rr, y: r.minY + ear))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: rr, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Fond d'écran original : dégradé indigo → magenta → orange et grandes vagues douces.
struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.14, blue: 0.55), Color(red: 0.62, green: 0.20, blue: 0.72),
                                    Color(red: 0.96, green: 0.36, blue: 0.52), Color(red: 1.0, green: 0.66, blue: 0.30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Vagues : larges ellipses inclinées, plus claires sur le dessus.
            ForEach(0..<3) { index in
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.2 - Double(index) * 0.05), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 1300, height: 640)
                    .rotationEffect(.degrees(-18))
                    .offset(x: CGFloat(index) * 120 - 60, y: 260 + CGFloat(index) * 150)
            }
            // Reflet de la vitre en haut.
            LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

/// Icône : écran de Mac au cadre noir, fond d'écran coloré et encoche avec une touche ambre.
struct NotchkitIcon: View {
    var body: some View {
        Squircle {
            ZStack(alignment: .top) {
                // Cadre de l'écran.
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
                Wallpaper()
                    .frame(width: 824 - 2 * 46, height: 824 - 2 * 46)
                    .clipShape(RoundedRectangle(cornerRadius: radius - 46, style: .continuous))
                    .padding(.top, 46)
                // Encoche : collée au bord haut de l'écran, avec un aperçu d'activité en ambre.
                NotchForm(ear: 22, bottom: 46)
                    .fill(.black)
                    .frame(width: 330, height: 120)
                    .overlay {
                        HStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(amber)
                                .frame(width: 44, height: 44)
                            Spacer()
                            Bars(color: amber, height: 44)
                        }
                        .padding(.horizontal, 52)
                        .padding(.top, 34)
                    }
                    .padding(.top, 46)
            }
        }
    }
}

@MainActor func save(_ view: some View, _ name: String) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { print("échec", name); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
    print("ok", name)
}

MainActor.assumeIsolated {
    // Usage : swiftc scripts/AppIcon.swift -o /tmp/appicon && /tmp/appicon (écrit AppIcon-1024.png)
    save(NotchkitIcon(), "AppIcon-1024.png")
}
