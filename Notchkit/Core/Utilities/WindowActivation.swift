import AppKit

/// Passage au premier plan d'une fenêtre de Notchkit (réglages, tutoriel).
///
/// Depuis macOS 14, `NSApp.activate()` est une demande « coopérative » : le système peut la refuser
/// quand l'app au premier plan ne cède pas sa place. Pour une app de barre des menus (`LSUIElement`),
/// c'était fréquent : après un clic sur la roue dentée de l'encoche (panneau qui ne s'active pas),
/// Notchkit devenait active un instant puis le Finder reprenait la main, et la fenêtre restait grisée.
/// Tant qu'une de ces fenêtres est ouverte, Notchkit devient donc une app ordinaire (icône dans le
/// Dock, choix du propriétaire le 30/10/2026), que macOS laisse passer au premier plan ; elle redevient
/// discrète à la fermeture de la dernière.
/// On vérifie encore l'activation et on insiste ; si macOS refuse toujours, la fenêtre flotte au-dessus
/// des autres jusqu'à ce que Notchkit devienne active (un clic dessus suffit).
/// La fenêtre suit le bureau courant (et s'affiche au-dessus d'une app en plein écran) : sinon elle
/// restait sur le bureau où elle avait été ouverte la première fois, et « Réglages… » choisi depuis un
/// autre bureau n'affichait rien (30/10/2026).
@MainActor
enum WindowActivation {
    static func bringToFront(_ window: NSWindow) {
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        track(window)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(150))
                if NSApp.isActive { break }
                NSApp.activate()
            }
            guard window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
            if !NSApp.isActive { floatUntilActive(window) }
        }
    }

    // MARK: Icône dans le Dock tant qu'une fenêtre est ouverte

    /// Fenêtres ouvertes par `bringToFront`, et l'observateur de fermeture de chacune.
    private static var openWindows: [ObjectIdentifier: NSObjectProtocol] = [:]

    private static func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard openWindows[id] == nil else { return }
        openWindows[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { windowWillClose(id) }
        }
    }

    private static func windowWillClose(_ id: ObjectIdentifier) {
        if let observer = openWindows.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        // Dernière fenêtre fermée : Notchkit redevient une app de barre des menus, sans icône.
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: Fenêtre flottante en dernier recours

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
