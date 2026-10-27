import SwiftUI

struct TogglesExpandedView: View {
    let module: TogglesModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        Group {
            if let end = module.cleaningEndsAt {
                cleaning(until: end)
            } else {
                grid
            }
        }
        .padding(10)
    }

    /// Grille des commutateurs : si elle ne tient pas en hauteur (petit widget, encoche basse), boutons
    /// plus petits, puis icônes seules, plutôt que des libellés coupés par le bas de la carte.
    private var grid: some View {
        ViewThatFits(in: .vertical) {
            grid(button: .large, labels: true)
            grid(button: .regular, labels: true)
            grid(button: .regular, labels: false)
        }
        .frame(maxHeight: .infinity)
    }

    private func grid(button: StandByButtonStyle.Size, labels: Bool) -> some View {
        let compact = size == .small || size == .mini
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: compact ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: compact || !labels ? 6 : 8) {
            toggle("Mode sombre", symbol: module.isDarkMode ? "moon.fill" : "moon", active: module.isDarkMode,
                   button: button, label: labels, action: module.toggleDarkMode)
            toggle("Anti-veille", symbol: module.isAntiSleepOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                   active: module.isAntiSleepOn, button: button, label: labels, action: module.toggleAntiSleep)
            toggle("Bureau", symbol: module.areDesktopIconsVisible ? "menubar.dock.rectangle" : "rectangle.dashed",
                   active: !module.areDesktopIconsVisible, button: button, label: labels, action: module.toggleDesktopIcons)
                .help(module.areDesktopIconsVisible ? "Masquer les icônes du bureau" : "Afficher les icônes du bureau")
            toggle("Nettoyage", symbol: "keyboard", active: false, button: button, label: labels, action: module.startCleaning)
                .help(module.needsAccessibility ? "Autorisation Accessibilité nécessaire" : "Verrouille le clavier pendant 60 s pour le nettoyer")
        }
    }

    private func toggle(_ title: LocalizedStringKey, symbol: String, active: Bool, button: StandByButtonStyle.Size,
                        label: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.standBy(button, active: active, circle: true))
            .accessibilityLabel(Text(title))
            if label {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Clavier verrouillé : décompte et gros bouton pour le libérer.
    private func cleaning(until end: Date) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(StandBy.amber)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clavier verrouillé")
                    .font(.system(size: 14, weight: .semibold))
                Text("Nettoyez tranquillement. Il se libère de lui-même.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(StandBy.amber)
            }
            Spacer(minLength: 0)
            Button("Déverrouiller", action: module.stopCleaning)
                .buttonStyle(.standBy(.regular, active: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
