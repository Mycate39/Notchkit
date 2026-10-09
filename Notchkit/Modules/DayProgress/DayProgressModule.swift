import SwiftUI
import Observation

/// Module Journée : barre de progression de la journée de travail (8 h – 18 h par défaut).
@MainActor
@Observable
final class DayProgressModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "dayprogress",
        name: "Journée",
        summary: "Une barre qui montre où vous en êtes de votre journée de travail.",
        systemImage: "sun.horizon",
        category: .widgets,
        tier: .free,
        defaultEnabled: false
    )

    /// Début et fin de la journée, en minutes depuis minuit.
    var startMinute: Int {
        didSet { UserDefaults.standard.set(startMinute, forKey: Keys.start) }
    }
    var endMinute: Int {
        didSet { UserDefaults.standard.set(endMinute, forKey: Keys.end) }
    }

    private enum Keys {
        static let start = "module.dayprogress.start"
        static let end = "module.dayprogress.end"
    }

    init(context: ModuleContext) {
        let defaults = UserDefaults.standard
        startMinute = defaults.object(forKey: Keys.start) as? Int ?? 8 * 60
        endMinute = defaults.object(forKey: Keys.end) as? Int ?? 18 * 60
    }

    var compactPriority: ModulePriority { .none }

    func miniView() -> AnyView {
        AnyView(DayProgressMiniView(module: self))
    }

    func expandedView() -> AnyView {
        AnyView(DayProgressExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(DayProgressSettingsView(module: self))
    }
}

/// Logique pure de la journée : progression et temps restant.
enum DayProgress {
    /// Minutes écoulées depuis minuit.
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) * 60 + Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60
    }

    /// Progression entre 0 et 1 (0 avant le début, 1 après la fin).
    static func fraction(at minute: Double, start: Int, end: Int) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, (minute - Double(start)) / Double(end - start)))
    }

    /// Minutes restantes avant la fin (0 après la fin).
    static func remaining(at minute: Double, end: Int) -> Int {
        max(0, Int((Double(end) - minute).rounded(.up)))
    }

    /// « 8:00 » pour 480.
    static func label(_ minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
    }
}

struct DayProgressExpandedView: View {
    let module: DayProgressModule

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let minute = DayProgress.minuteOfDay(context.date)
            let fraction = DayProgress.fraction(at: minute, start: module.startMinute, end: module.endMinute)
            let remaining = DayProgress.remaining(at: minute, end: module.endMinute)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tint)
                    Spacer()
                    Group {
                        if fraction >= 1 {
                            Text("Journée terminée")
                        } else if fraction <= 0 {
                            Text("La journée n'a pas commencé")
                        } else {
                            Text("Encore \(Duration.seconds(remaining * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
                StandByBar(value: fraction, height: 10)
                HStack {
                    Text(DayProgress.label(module.startMinute))
                    Spacer()
                    Text(DayProgress.label(module.endMinute))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
            .frame(maxHeight: .infinity)
        }
    }
}

struct DayProgressMiniView: View {
    let module: DayProgressModule

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let fraction = DayProgress.fraction(at: DayProgress.minuteOfDay(context.date),
                                                start: module.startMinute, end: module.endMinute)
            MiniWidget(value: fraction.formatted(.percent.precision(.fractionLength(0))),
                       caption: String(localized: "Journée")) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 5)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(3)
            }
        }
    }
}

struct DayProgressSettingsView: View {
    @Bindable var module: DayProgressModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $module.startMinute, in: 0...(module.endMinute - 30), step: 30) {
                LabeledContent("Début de la journée", value: DayProgress.label(module.startMinute))
            }
            Stepper(value: $module.endMinute, in: (module.startMinute + 30)...(24 * 60), step: 30) {
                LabeledContent("Fin de la journée", value: DayProgress.label(module.endMinute))
            }
        }
    }
}
