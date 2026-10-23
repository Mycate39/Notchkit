import AppKit

/// Passage au premier plan d'une fenêtre de Notchkit (réglages, tutoriel).
///
/// Depuis macOS 14, `NSApp.activate()` est une demande « coopérative » : le système peut la refuser
/// quand l'app au premier plan ne cède pas sa place, par exemple après un clic dans l'encoche, panneau
/// qui ne s'active pas. La fenêtre passe alors devant mais reste grisée, et la barre des menus reste
/// celle de l'autre app. On vérifie donc l'activation et on insiste si elle a échoué.
@MainActor
enum WindowActivation {
    static func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(120))
                if NSApp.isActive { break }
                // Demande non coopérative (dépréciée mais toujours honorée pour une app de barre des menus).
                NSApp.activate(ignoringOtherApps: true)
            }
            if window.isVisible { window.makeKeyAndOrderFront(nil) }
        }
    }
}
