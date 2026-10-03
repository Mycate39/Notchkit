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

        #if DEBUG
        Divider()

        // Menu réservé aux versions de développement.
        Menu("Débogage") {
            Button("Afficher une alerte de test") {
                appDelegate.presentTestAlert()
            }

            Divider()

            Button("Batterie : simuler le branchement") {
                appDelegate.simulateBattery(.pluggedIn)
            }
            Button("Batterie : simuler le débranchement") {
                appDelegate.simulateBattery(.unplugged)
            }
            Button("Batterie : simuler la batterie faible") {
                appDelegate.simulateBattery(.low(threshold: 10))
            }
        }
        #endif

        Divider()

        Button("Quitter Notchkit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
