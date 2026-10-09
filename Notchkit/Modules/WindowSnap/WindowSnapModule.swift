import AppKit
import SwiftUI
import Observation

/// Module Ancrage des fenêtres : glisser une fenêtre vers l'encoche propose des zones (moitiés,
/// tiers, quarts, plein écran) où la déposer. Fonctionne en arrière-plan, sans carte.
@MainActor
@Observable
final class WindowSnapModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "windowsnap",
        name: "Ancrage des fenêtres",
        summary: "Glissez une fenêtre vers l'encoche pour la ranger en moitié, tiers, quart ou plein écran.",
        systemImage: "rectangle.split.2x1",
        category: .system,
        tier: .free,
        defaultEnabled: false,
        providesWidget: false
    )

    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private let snapper = WindowSnapper()

    init(context: ModuleContext) {}

    func start() {
        guard !AutomatedRun.isActive else { return }
        snapper.start()
    }

    func stop() {
        snapper.stop()
    }

    func requestAccessibility() {
        MediaKeyTap.requestTrust()
        MediaKeyTap.openAccessibilitySettings()
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                if AXIsProcessTrusted() { isTrusted = true; return }
            }
        }
    }

    var compactPriority: ModulePriority { .none }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView? { AnyView(WindowSnapSettingsView(module: self)) }
}

struct WindowSnapSettingsView: View {
    let module: WindowSnapModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Faites glisser une fenêtre par sa barre de titre vers le haut de l'écran : des zones apparaissent sous l'encoche. Relâchez sur une zone pour y ranger la fenêtre.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !module.isTrusted {
                HStack {
                    Label("Autorisation Accessibilité nécessaire", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Autoriser…", action: module.requestAccessibility)
                }
            }
        }
    }
}
