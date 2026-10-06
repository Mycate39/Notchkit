import CoreGraphics
import Testing
@testable import Notchkit

/// Détection d'une barre des menus sombre d'après la bande du haut du fond d'écran.
struct MenuBarToneTests {
    /// Image de 100×100 : `top` sur les 10 % du haut, `bottom` ailleurs (niveaux de gris 0…1).
    private func image(top: CGFloat, bottom: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: bottom, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 90))
        // Origine en bas à gauche : le haut de l'image est à y = 90…100.
        context.setFillColor(CGColor(gray: top, alpha: 1))
        context.fill(CGRect(x: 0, y: 90, width: 100, height: 10))
        return context.makeImage()
    }

    @Test func hautSombreFondClair() throws {
        let picture = try #require(image(top: 0.05, bottom: 0.95))
        let luminance = try #require(MenuBarTone.topLuminance(of: picture))
        #expect(luminance < MenuBarTone.darkThreshold)
    }

    @Test func hautClairFondSombre() throws {
        let picture = try #require(image(top: 0.95, bottom: 0.05))
        let luminance = try #require(MenuBarTone.topLuminance(of: picture))
        #expect(luminance > MenuBarTone.darkThreshold)
    }
}
