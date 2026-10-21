import SwiftUI

/// Point d'entrée de Notchkit.
/// L'app n'a pas de fenêtre principale : seulement une icône dans la barre des menus
/// (LSUIElement = YES dans Info.plist) et le panneau de l'encoche.
@main
struct NotchkitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // L'icône peut être masquée dans les réglages (ou retirée de la barre avec ⌘ + glisser).
        MenuBarExtra("Notchkit", systemImage: "rectangle.topthird.inset.filled", isInserted: Binding(
            get: { appDelegate.settings.settings.showsMenuBarIcon },
            // N'écrire que si la valeur change : sinon enregistrement → nouvelle évaluation de la scène → boucle.
            set: { if appDelegate.settings.settings.showsMenuBarIcon != $0 { appDelegate.settings.settings.showsMenuBarIcon = $0 } }
        )) {
            MenuBarContent(appDelegate: appDelegate)
        }
    }
}
