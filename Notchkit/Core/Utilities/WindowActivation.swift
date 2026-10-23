import AppKit

/// Passage au premier plan d'une fenêtre de Notchkit (réglages, tutoriel).
///
/// Depuis macOS 14, `NSApp.activate()` est une demande « coopérative » : le système peut la refuser
/// quand l'app au premier plan ne cède pas sa place, par exemple après un clic dans l'encoche, panneau
/// qui ne s'active pas, ou au premier lancement depuis le Finder (alerte de Gatekeeper comprise).
/// La fenêtre resterait grisée, voire derrière d'autres fenêtres. On vérifie donc l'activation, on
/// insiste, et si macOS refuse toujours, la fenêtre flotte au-dessus des autres jusqu'à ce que
/// Notchkit devienne active (un clic dessus suffit), puis reprend son niveau normal.
@MainActor
enum WindowActivation {
    static func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(150))
                if NSApp.isActive { break }
                // Demande non coopérative (dépréciée mais toujours honorée pour une app de barre des menus).
                NSApp.activate(ignoringOtherApps: true)
            }
            guard window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
            if !NSApp.isActive { floatUntilActive(window) }
        }
    }

    /// Fenêtres qui flottent en attendant l'activation, et l'observateur qui les rend à leur niveau.
    private static var floatingWindows: [NSWindow] = []
    private static var activeObserver: NSObjectProtocol?

    /// Garde la fenêtre visible au-dessus des autres apps tant que Notchkit n'est pas active.
    private static func floatUntilActive(_ window: NSWindow) {
        window.level = .floating
        window.orderFrontRegardless()
        if !floatingWindows.contains(window) { floatingWindows.append(window) }
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                floatingWindows.forEach { $0.level = .normal }
                floatingWindows.removeAll()
            }
        }
    }
}
