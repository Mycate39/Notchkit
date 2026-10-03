import SwiftUI

/// Menu de l'icône Notchkit dans la barre des menus.
struct MenuBarContent: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Déplier / replier l'encoche") {
            appDelegate.viewModel.toggle()
        }

        Button("Réglages…") {
            appDelegate.showSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Menu("Débogage") {
            Button("Afficher une alerte de test") {
                appDelegate.presentTestAlert()
            }
        }

        Divider()

        Button("Quitter Notchkit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
