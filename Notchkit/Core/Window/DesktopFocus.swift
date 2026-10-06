import AppKit
import CoreGraphics

/// Savoir si l'on est « sur le bureau » : le Finder au premier plan, sans aucune de ses fenêtres
/// ouverte à l'écran (seuls le fond d'écran et les icônes du bureau sont visibles).
///
/// La liste des fenêtres (propriétaire et niveau, sans les titres) se lit sans autorisation.
enum DesktopFocus {
    static let finderBundleID = "com.apple.finder"

    @MainActor
    static func isOnDesktop() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == finderBundleID
        else { return false }
        return !hasVisibleWindows(ownerPID: app.processIdentifier)
    }

    /// Fenêtres ordinaires (niveau 0) de ce processus affichées sur le bureau actuel,
    /// hors fenêtre des icônes du bureau.
    static func hasVisibleWindows(ownerPID: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return windows.contains { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == ownerPID
                && (window[kCGWindowLayer as String] as? Int) == 0
        }
    }
}
