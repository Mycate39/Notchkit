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

    /// Fuseau horaire secondaire affiché sous l'heure locale (`nil` = aucun).
    var secondaryTimeZoneID: String? {
        didSet { UserDefaults.standard.set(secondaryTimeZoneID, forKey: Keys.secondaryTimeZone) }
    }

    private enum Keys {
        static let showInCompact = "module.clock.showInCompact"
        static let secondaryTimeZone = "module.clock.secondaryTimeZone"
    }

    /// Villes proposées pour le second fuseau horaire.
    static let worldCities: [(name: LocalizedStringResource, timeZone: String)] = [
        ("Londres", "Europe/London"),
        ("Paris", "Europe/Paris"),
        ("Moscou", "Europe/Moscow"),
        ("Dubaï", "Asia/Dubai"),
        ("Mumbai", "Asia/Kolkata"),
        ("Singapour", "Asia/Singapore"),
        ("Shanghai", "Asia/Shanghai"),
        ("Tokyo", "Asia/Tokyo"),
        ("Sydney", "Australia/Sydney"),
        ("São Paulo", "America/Sao_Paulo"),
        ("New York", "America/New_York"),
        ("Montréal", "America/Toronto"),
        ("Chicago", "America/Chicago"),
        ("Los Angeles", "America/Los_Angeles"),
        ("UTC", "UTC"),
    ]

    init(context: ModuleContext) {
        showInCompact = UserDefaults.standard.object(forKey: Keys.showInCompact) as? Bool ?? true
        secondaryTimeZoneID = UserDefaults.standard.string(forKey: Keys.secondaryTimeZone)
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

    func miniView() -> AnyView {
        AnyView(ClockMiniView())
    }

    func expandedView() -> AnyView {
        AnyView(ClockExpandedView(secondaryTimeZoneID: secondaryTimeZoneID))
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

/// Heure avec secondes, date complète et éventuel second fuseau horaire.
private struct ClockExpandedView: View {
    let secondaryTimeZoneID: String?
    @Environment(\.widgetSize) private var size

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: size == .large ? 42 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(nil)
                if let secondary = secondaryTimeZoneID.flatMap(TimeZone.init(identifier:)) {
                    Text(secondaryLabel(secondary, date: context.date))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(12)
        }
    }
}

extension ClockExpandedView {
    /// Ex. « Tokyo 17:27 (+7 h) ».
    private func secondaryLabel(_ zone: TimeZone, date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        let name = ClockModule.worldCities.first { $0.timeZone == zone.identifier }.map { String(localized: $0.name) }
            ?? zone.identifier
        let offsetHours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        let offset = offsetHours == 0 ? "" : " (\(offsetHours > 0 ? "+" : "")\(offsetHours.formatted(.number.precision(.fractionLength(0...1)))) h)"
        return "\(name) \(date.formatted(style))\(offset)"
    }
}

private struct ClockSettingsView: View {
    @Bindable var module: ClockModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Afficher l'heure quand l'encoche est repliée", isOn: $module.showInCompact)
            Picker("Second fuseau horaire", selection: $module.secondaryTimeZoneID) {
                Text("Aucun").tag(String?.none)
                ForEach(ClockModule.worldCities, id: \.timeZone) { city in
                    Text(city.name).tag(Optional(city.timeZone))
                }
            }
        }
    }
}

/// Heure en version Mini : chiffres aussi grands que le widget le permet.
private struct ClockMiniView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let parts = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let hour = String(format: "%02d", parts.hour ?? 0)
                let minute = String(format: "%02d", parts.minute ?? 0)

                Group {
                    if height < 100 {
                        // Empilé (demi-hauteur) : une seule ligne.
                        Text("\(hour):\(minute)")
                            .font(.system(size: min(width * 0.3, height * 0.4), weight: .bold, design: .rounded))
                    } else {
                        VStack(spacing: -height * 0.03) {
                            Text(hour)
                            Text(minute)
                            Text(context.date, format: .dateTime.weekday(.abbreviated).day())
                                .font(.system(size: max(8, width * 0.14), weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.top, height * 0.05)
                        }
                        .font(.system(size: min(width * 0.46, height * 0.26), weight: .bold, design: .rounded))
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: width, height: height)
            }
        }
    }
}
