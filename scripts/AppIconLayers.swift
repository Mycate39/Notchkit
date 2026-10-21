import AppKit
import SwiftUI

// Couches de l'icône de Notchkit au format Icon Composer (macOS 26+) : macOS ajoute lui-même le verre,
// les reflets, l'ombre et les variantes (sombre, transparente, teintée). Chaque couche est une image
// 1024 × 1024 transparente, à sa place sur la toile de l'icône (pleine, sans marge).
// Usage : swiftc scripts/AppIconLayers.swift -o /tmp/appicon-layers && /tmp/appicon-layers <dossier Assets>
let canvas: CGFloat = 1024
let amber = Color(red: 1.0, green: 0.62, blue: 0.16)

/// Encoche collée en haut : congés concaves et bas arrondi (comme dans l'app).
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

/// Place de l'encoche sur la toile.
let notchFrame = CGRect(x: 132, y: 0, width: 760, height: 330)

/// Couche 1 : l'encoche noire, suspendue au bord haut de l'icône.
struct NotchLayer: View {
    var body: some View {
        NotchForm(ear: 46, bottom: 120)
            .fill(.black)
            .frame(width: notchFrame.width, height: notchFrame.height)
            .position(x: notchFrame.midX, y: notchFrame.midY)
            .frame(width: canvas, height: canvas)
    }
}

/// Couche 2 : l'aperçu d'activité à gauche (carré ambre, comme une pochette).
struct ArtworkLayer: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(amber)
            .frame(width: 128, height: 128)
            .position(x: notchFrame.minX + 46 + 100 + 64, y: 172)
            .frame(width: canvas, height: canvas)
    }
}

/// Couche 3 : les barres de son à droite, en cloche.
struct BarsLayer: View {
    var body: some View {
        let height: CGFloat = 132
        HStack(alignment: .center, spacing: height * 0.13) {
            ForEach([0.35, 0.6, 0.85, 1.0, 0.85, 0.6, 0.35], id: \.self) { h in
                Capsule().fill(amber).frame(width: height * 0.12, height: height * h)
            }
        }
        .frame(height: height)
        .position(x: notchFrame.maxX - 46 - 100 - 80, y: 172)
        .frame(width: canvas, height: canvas)
    }
}

@MainActor func save(_ view: some View, _ url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { print("échec", url.lastPathComponent); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("ok", url.lastPathComponent)
}

MainActor.assumeIsolated {
    let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    save(NotchLayer(), folder.appendingPathComponent("notch.png"))
    save(ArtworkLayer(), folder.appendingPathComponent("artwork.png"))
    save(BarsLayer(), folder.appendingPathComponent("bars.png"))
}
