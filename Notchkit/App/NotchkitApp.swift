import SwiftUI

/// Point d'entrée de Notchkit.
/// L'app n'a pas de fenêtre principale : seulement une icône dans la barre des menus
/// (LSUIElement = YES dans Info.plist) et le panneau de l'encoche.
@main
struct NotchkitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notchkit", systemImage: "rectangle.topthird.inset.filled") {
            MenuBarContent(appDelegate: appDelegate)
        }
    }
}
