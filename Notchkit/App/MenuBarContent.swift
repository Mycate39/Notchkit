import SwiftUI

/// Menu de l'icône Notchkit dans la barre des menus.
struct MenuBarContent: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Déplier / replier l'encoche") {
            appDelegate.viewModel.toggle()
        }

        if let gameMode = appDelegate.moduleManager.module(for: GameModeModule.descriptor.id) as? GameModeModule {
            Toggle("Mode jeu", isOn: Binding(get: { gameMode.isActive }, set: { gameMode.setManual($0) }))
        }

        Divider()

        Button("Réglages…") {
            appDelegate.showSettings()
        }
        .keyboardShortcut(",")

        Button("Revoir le tutoriel…") {
            appDelegate.showOnboarding()
        }

        Button("Rechercher les mises à jour…") {
            Updater.shared.checkForUpdates()
        }
        .disabled(!Updater.shared.isAvailable)

        Divider()

        Button("À propos de Notchkit") {
            appDelegate.showSettings(tab: .about)
        }

        Button("Copier les informations de diagnostic") {
            appDelegate.copyDiagnostics()
        }

        #if DEBUG
        Divider()

        // Menu réservé aux versions de développement.
        Menu("Débogage") {
            Button("Afficher une alerte de test") {
                appDelegate.presentTestAlert()
            }
            Toggle("Animations au ralenti (×8)", isOn: Binding(
                get: { NotchLayout.animationSlowdown > 1 },
                set: { NotchLayout.animationSlowdown = $0 ? 8 : 1 }
            ))

            Divider()

            Button("Aperçu : déverrouillage Touch ID") { appDelegate.previewUnlock("unlock") }
            Button("Aperçu : demande Touch ID") { appDelegate.previewUnlock("touchID") }
            Button("Aperçu : demande de mot de passe") { appDelegate.previewUnlock("password") }

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
