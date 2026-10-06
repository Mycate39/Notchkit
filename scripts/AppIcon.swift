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

// C. Minimal clair : squircle argenté, encoche noire suspendue avec sa mini-encoche.
struct ConceptMinimal: View {
    var body: some View {
        Squircle {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(white: 0.98), Color(white: 0.84)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .top, spacing: 18) {
                    NotchForm(ear: 26, bottom: 64)
                        .fill(.black)
                        .frame(width: 470, height: 190)
                        .overlay {
                            HStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(amber).frame(width: 74, height: 74)
                                Spacer()
                                Bars(color: amber, height: 70)
                            }
                            .padding(.horizontal, 64).padding(.top, 16)
                        }
                    NotchForm(ear: 26, bottom: 64)
                        .fill(.black)
                        .frame(width: 170, height: 190)
                        .overlay {
                            Image(systemName: "timer").font(.system(size: 70, weight: .semibold)).foregroundStyle(amber)
                                .padding(.top, 16)
                        }
                }
                .padding(.leading, 60)
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
    save(ConceptMinimal(), "AppIcon-1024.png")
}
