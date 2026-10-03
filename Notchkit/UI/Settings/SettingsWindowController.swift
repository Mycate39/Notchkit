import AppKit
import SwiftUI

/// Fenêtre de réglages, gérée manuellement : plus fiable que la scène `Settings` de SwiftUI
/// pour une app sans icône dans le Dock (elle passe correctement au premier plan).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: @MainActor () -> AnyView

    init(makeContent: @escaping @MainActor () -> AnyView) {
        self.makeContent = makeContent
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "Réglages de Notchkit")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
