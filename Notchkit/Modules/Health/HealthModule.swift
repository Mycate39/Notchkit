import SwiftUI
import Observation

/// Règles pures des rappels de santé (testées sans horloge).
enum HealthRules {
    static let breakAfter: TimeInterval = 50 * 60
    static let breakRepeat: TimeInterval = 10 * 60
    static let waterEvery: TimeInterval = 60 * 60
    /// Objectifs quotidiens des anneaux.
    static let pauseGoal = 6
    static let waterGoal = 8
    static let activeGoal: TimeInterval = 8 * 3600

    /// Pause conseillée : 50 min d'activité continue, puis toutes les 10 min sans pause.
    static func shouldRemindBreak(streakStart: Date?, lastReminder: Date?, now: Date) -> Bool {
        guard let streakStart, now.timeIntervalSince(streakStart) >= breakAfter else { return false }
        guard let lastReminder, lastReminder >= streakStart else { return true }
        return now.timeIntervalSince(lastReminder) >= breakRepeat
    }

    /// Verre d'eau conseillé toutes les 60 min depuis le dernier verre (ou le dernier rappel).
    static func shouldRemindWater(lastDrink: Date, lastReminder: Date?, now: Date) -> Bool {
        let reference = max(lastDrink, lastReminder ?? .distantPast)
        return now.timeIntervalSince(reference) >= waterEvery
    }
}

/// Module Santé : rappels de pause et d'hydratation, et anneaux de la journée. Tout est mesuré
/// sur ce Mac (activité clavier/souris), sans données Santé.
@MainActor
@Observable
final class HealthModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "health",
        name: "Santé",
        summary: "Rappels de pause et d'hydratation, et anneaux de votre journée devant le Mac.",
        systemImage: "figure.walk",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    static let tick: TimeInterval = 30

    private(set) var pauses = 0
    private(set) var glasses = 0
    private(set) var activeSeconds: Double = 0
    private(set) var streakStart: Date?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var day = ActivityClock.dayKey(Date())
    @ObservationIgnored private var lastDrink = Date()
    @ObservationIgnored private var lastBreakReminder: Date?
    @ObservationIgnored private var lastWaterReminder: Date?

    private enum Keys {
        static let state = "module.health.today"
    }

    init(context: ModuleContext) {
        self.context = context
        // Compteurs du jour (repartent de zéro le lendemain).
        if let stored = UserDefaults.standard.dictionary(forKey: Keys.state),
           stored["day"] as? String == day {
            pauses = stored["pauses"] as? Int ?? 0
            glasses = stored["glasses"] as? Int ?? 0
            activeSeconds = stored["active"] as? Double ?? 0
        }
    }

    func start() {
        guard loop == nil, !AutomatedRun.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tick))
                self?.update(now: Date())
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        save()
    }

    func drankGlass() {
        withAnimation(.snappy) { glasses += 1 }
        lastDrink = Date()
        save()
    }

    private func update(now: Date) {
        let today = ActivityClock.dayKey(now)
        if today != day {
            day = today
            pauses = 0
            glasses = 0
            activeSeconds = 0
        }
        let idle = ActivityClock.secondsSinceLastInput
        if ActivityClock.isActive(idle: idle) { activeSeconds += Self.tick }

        let next = ActivityClock.streakStart(previous: streakStart, idle: idle, now: now)
        if streakStart != nil, next == nil { pauses += 1 }
        streakStart = next

        if HealthRules.shouldRemindBreak(streakStart: streakStart, lastReminder: lastBreakReminder, now: now) {
            lastBreakReminder = now
            context.presentAlert(HealthAlerts.takeBreak())
        } else if ActivityClock.isActive(idle: idle),
                  HealthRules.shouldRemindWater(lastDrink: lastDrink, lastReminder: lastWaterReminder, now: now) {
            lastWaterReminder = now
            context.presentAlert(HealthAlerts.drinkWater())
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(["day": day, "pauses": pauses, "glasses": glasses, "active": activeSeconds],
                                  forKey: Keys.state)
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(value: "\(glasses)/\(HealthRules.waterGoal)", caption: String(localized: "Santé")) {
            HealthRings(module: self, lineWidth: 4)
        })
    }

    func expandedView() -> AnyView { AnyView(HealthExpandedView(module: self)) }
}

enum HealthAlerts {
    @MainActor
    static func takeBreak() -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "figure.walk").foregroundStyle(.green)),
            trailing: AnyView(Text("Faites une pause").foregroundStyle(.green).minimumScaleFactor(0.7)),
            duration: .seconds(6)
        )
    }

    @MainActor
    static func drinkWater() -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "drop.fill").foregroundStyle(.cyan)),
            trailing: AnyView(Text("Un verre d'eau ?").foregroundStyle(.cyan).minimumScaleFactor(0.7)),
            duration: .seconds(6)
        )
    }
}

/// Trois anneaux concentriques : pauses (vert), eau (cyan), temps actif (ambre).
struct HealthRings: View {
    let module: HealthModule
    var lineWidth: CGFloat = 7

    var body: some View {
        let rings: [(Double, Color)] = [
            (Double(module.pauses) / Double(HealthRules.pauseGoal), .green),
            (Double(module.glasses) / Double(HealthRules.waterGoal), .cyan),
            (module.activeSeconds / HealthRules.activeGoal, StandBy.amber),
        ]
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                let inset = CGFloat(index) * (lineWidth + 3.5)
                Circle().stroke(ring.1.opacity(0.2), lineWidth: lineWidth).padding(inset)
                Circle().trim(from: 0, to: min(1, ring.0))
                    .stroke(ring.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .padding(lineWidth / 2)
        .animation(.snappy, value: module.glasses)
    }
}

struct HealthExpandedView: View {
    let module: HealthModule

    var body: some View {
        HStack(spacing: 14) {
            HealthRings(module: module)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 5) {
                row(color: .green, text: "Pauses : \(module.pauses)/\(HealthRules.pauseGoal)")
                row(color: .cyan, text: "Eau : \(module.glasses)/\(HealthRules.waterGoal) verres")
                row(color: StandBy.amber, text: "Actif : \(ScreenTimeFormat.duration(module.activeSeconds))")
                if let start = module.streakStart {
                    Text("Sans pause depuis \(ScreenTimeFormat.duration(Date().timeIntervalSince(start)))")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Button(action: module.drankGlass) {
                    Label("J'ai bu un verre", systemImage: "drop.fill")
                }
                .buttonStyle(.standBy(.small))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func row(color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
    }
}
