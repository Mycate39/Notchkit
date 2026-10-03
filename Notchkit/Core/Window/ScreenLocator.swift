import AppKit

/// Trouve l'écran cible et calcule la géométrie de l'encoche (API publiques uniquement).
@MainActor
enum ScreenLocator {
    /// Taille de la fausse encoche en mode simulation (proche d'un MacBook Pro 14").
    static let simulatedNotchSize = CGSize(width: 185, height: 32)
    /// Largeur de la pastille au repos (Mac sans encoche).
    static let pillWidth: CGFloat = 96

    /// Écran correspondant à la sélection ; repli sur l'écran principal s'il est débranché.
    static func screen(for selection: ScreenSelection) -> NSScreen? {
        switch selection {
        case .primary:
            return NSScreen.screens.first
        case let .specific(id, _):
            return NSScreen.screens.first { $0.notchkitID == id } ?? NSScreen.screens.first
        }
    }

    static func geometry(for screen: NSScreen, simulateNotch: Bool) -> NotchGeometry {
        let frame = screen.frame

        // Encoche réelle : macOS la signale via la zone de sécurité et les deux zones
        // libres de part et d'autre (auxiliaryTopLeftArea / auxiliaryTopRightArea).
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = frame.width - left.width - right.width
            return NotchGeometry(
                style: .notch,
                closedSize: CGSize(width: notchWidth, height: screen.safeAreaInsets.top),
                screenFrame: frame,
                centerX: frame.minX + left.width + notchWidth / 2
            )
        }

        if simulateNotch {
            return NotchGeometry(
                style: .notch,
                closedSize: simulatedNotchSize,
                screenFrame: frame,
                centerX: frame.midX
            )
        }

        // Pas d'encoche : pastille flottante, dimensionnée d'après la barre des menus.
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        let barHeight = menuBarHeight > 0 ? menuBarHeight : 24
        return NotchGeometry(
            style: .pill,
            closedSize: CGSize(width: pillWidth, height: max(barHeight - NotchLayout.pillTopInset - 1, 20)),
            screenFrame: frame,
            centerX: frame.midX
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Identifiant stable de l'écran (UUID), contrairement au numéro d'écran qui peut changer.
    var notchkitID: String? {
        guard let displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }
}
