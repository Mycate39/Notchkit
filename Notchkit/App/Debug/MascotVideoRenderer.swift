#if DEBUG
import AppKit
import SwiftUI

/// Outil de développement : rend, image par image, une courte démonstration des animations de la
/// mascotte (une humeur toutes les trois secondes). Lancer l'app avec `NOTCHKIT_MASCOT_VIDEO=/dossier`,
/// puis assembler les images avec ffmpeg (30 images par seconde).
@MainActor
enum MascotVideoRenderer {
    static let fps = 30
    static let secondsPerMood = 3.0
    static let moods: [(MascotMood, String)] = [
        (.idle, "Au repos"), (.working, "Au travail"), (.waiting, "Attend ta réponse"),
        (.happy, "Terminé !"), (.angry, "Pas content"),
    ]

    static func renderFrames(design: MascotDesign, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = Int(secondsPerMood * Double(moods.count) * Double(fps))
        for frame in 0..<total {
            let time = Double(frame) / Double(fps)
            let index = min(moods.count - 1, Int(time / secondsPerMood))
            let local = time - Double(index) * secondsPerMood
            let (mood, label) = moods[index]
            let pose = MascotMotion.pose(at: local, mood: mood)
            let view = ZStack {
                RadialGradient(colors: [Color(white: 0.12), .black], center: .center, startRadius: 0, endRadius: 520)
                VStack(spacing: 34) {
                    MascotPoseView(design: design, mood: mood, pose: pose, gaze: nil, size: 220)
                        .frame(height: 360)
                    Text(label)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(design.name)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 1280, height: 720)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appendingPathComponent(String(format: "frame%04d.png", frame)))
        }
    }
}
#endif
