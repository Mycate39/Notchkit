import SwiftUI
import Observation

/// Module de démonstration : affiche l'heure.
/// Sert de modèle pour les futurs modules (vue compacte, vue étendue, réglages propres).
@MainActor
@Observable
final class ClockModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "clock",
        name: "Horloge",
        summary: "Affiche l'heure et la date.",
        systemImage: "clock",
        category: .widgets,
        tier: .free,
        defaultEnabled: true
    )

    /// Affiche l'heure quand l'encoche est repliée.
    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }

    private enum Keys {
        static let showInCompact = "module.clock.showInCompact"
    }

    init(context: ModuleContext) {
        showInCompact = UserDefaults.standard.object(forKey: Keys.showInCompact) as? Bool ?? true
    }

    // Pas de start()/stop() : les vues utilisent `TimelineView`, qui ne se rafraîchit
    // que lorsqu'elles sont affichées. Rien ne tourne en arrière-plan.

    var compactPriority: ModulePriority {
        showInCompact ? .low : .none
    }

    func compactLeading() -> AnyView? {
        AnyView(
            Image(systemName: "clock.fill")
                .foregroundStyle(.white.opacity(0.8))
        )
    }

    func compactTrailing() -> AnyView? {
        AnyView(ClockCompactText())
    }

    func expandedView() -> AnyView {
        AnyView(ClockExpandedView())
    }

    func settingsView() -> AnyView? {
        AnyView(ClockSettingsView(module: self))
    }
}

// MARK: - Vues

/// Heure courte, rafraîchie une fois par minute seulement.
private struct ClockCompactText: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .monospacedDigit()
        }
    }
}

/// Heure avec secondes et date complète.
private struct ClockExpandedView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(nil)
            }
            .padding(12)
        }
    }
}

private struct ClockSettingsView: View {
    @Bindable var module: ClockModule

    var body: some View {
        Toggle("Afficher l'heure quand l'encoche est repliée", isOn: $module.showInCompact)
    }
}
