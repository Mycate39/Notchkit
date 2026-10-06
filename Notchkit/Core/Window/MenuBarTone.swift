import AppKit
import ImageIO

/// Teinte de la barre des menus, pour savoir si l'encoche noire s'y fond (barre sombre) ou non.
///
/// Depuis macOS 26, la barre des menus est transparente : sa couleur visible est celle du haut du
/// fond d'écran. On lit donc une vignette du fond d'écran (API publique, sans autorisation) et on
/// mesure la luminosité de sa bande supérieure. Fond illisible : on suit le mode sombre de macOS.
enum MenuBarTone {
    /// En dessous de cette luminance (0…1), la barre est considérée comme sombre.
    static let darkThreshold = 0.35

    /// Barre des menus sombre sur cet écran ? (lecture du fichier hors du fil principal)
    static func isDark(wallpaper url: URL?, systemIsDark: Bool) async -> Bool {
        guard let url else { return systemIsDark }
        let luminance = await Task.detached(priority: .utility) { topLuminance(of: url) }.value
        return luminance.map { $0 < darkThreshold } ?? systemIsDark
    }

    /// Luminance moyenne de la bande supérieure (4 %) d'une image, `nil` si illisible.
    static func topLuminance(of url: URL) -> Double? {
        // Vignette : rapide même pour les fonds dynamiques de plusieurs dizaines de Mo.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return topLuminance(of: image)
    }

    static func topLuminance(of image: CGImage) -> Double? {
        let width = 32, height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // On dessine l'image de façon que seule sa bande du haut (4 %) remplisse le contexte.
            let scaledHeight = CGFloat(height) / 0.04
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: CGFloat(height) - scaledHeight,
                                           width: CGFloat(width), height: scaledHeight))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            total += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return total / Double(width * height)
    }
}
