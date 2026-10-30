import SwiftUI

// MARK: - Couleurs

enum BatteryStyle {
    /// Couleur de remplissage de la jauge : vert en charge, jaune en économie d'énergie,
    /// rouge si faible, blanc sinon (conventions d'iOS et de macOS).
    static func fillColor(for state: BatteryState, isLowPowerMode: Bool) -> Color {
        if state.isPluggedIn && state.status != .pluggedNotCharging { return .green }
        if isLowPowerMode { return .yellow }
        if state.isLow { return .red }
        return .white
    }

    static func textColor(for state: BatteryState, isLowPowerMode: Bool) -> Color {
        let fill = fillColor(for: state, isLowPowerMode: isLowPowerMode)
        return fill == .white ? .white : fill
    }
}

// MARK: - Jauge

/// Icône de batterie de macOS 27 : capsule grise remplie de blanc (ou de la couleur d'état) selon
/// le niveau, pourcentage évidé au centre, éclair évidé à côté pendant la charge, petite borne à droite.
struct BatteryGlyph: View {
    var level: Double
    var color: Color
    var showsBolt: Bool
    var size: CGSize

    static let defaultSize = CGSize(width: 25, height: 12)

    init(level: Double, color: Color, showsBolt: Bool, size: CGSize = BatteryGlyph.defaultSize) {
        self.level = level
        self.color = color
        self.showsBolt = showsBolt
        self.size = size
    }

    init(state: BatteryState, isLowPowerMode: Bool, size: CGSize = BatteryGlyph.defaultSize) {
        self.init(
            level: state.fraction,
            color: BatteryStyle.fillColor(for: state, isLowPowerMode: isLowPowerMode),
            showsBolt: state.isPluggedIn,
            size: size
        )
    }

    /// Pourcentage affiché dans la jauge (fonction pure, testée).
    static func percentage(for level: Double) -> Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }

    var body: some View {
        let height = size.height
        let capsule = RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
        let capWidth = max(1.5, height * 0.12)
        let fraction = min(max(level, 0), 1)

        HStack(spacing: max(0.75, height * 0.07)) {
            ZStack(alignment: .leading) {
                capsule.fill(.white.opacity(0.38))
                // Remplissage à bord droit, découpé par la capsule.
                Rectangle()
                    .fill(color)
                    .frame(width: size.width * fraction)
                // Chiffres (et éclair) évidés : on voit le fond de l'encoche à travers.
                HStack(spacing: height * 0.04) {
                    Text(verbatim: "\(Self.percentage(for: level))")
                        .font(.system(size: height * 0.76, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText(value: fraction))
                    if showsBolt {
                        BatteryBoltShape()
                            .frame(width: height * 0.36, height: height * 0.62)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, height * 0.12)
                .frame(width: size.width, height: height)
                .blendMode(.destinationOut)
            }
            .frame(width: size.width, height: height)
            .clipShape(capsule)
            .compositingGroup()

            // Borne de la batterie
            UnevenRoundedRectangle(bottomTrailingRadius: capWidth, topTrailingRadius: capWidth, style: .continuous)
                .fill(.white.opacity(0.38))
                .frame(width: capWidth, height: height * 0.38)
        }
    }
}

// MARK: - Alertes

enum BatteryAlertFactory {
    @MainActor
    static func alert(for event: BatteryEvent, state: BatteryState) -> NotchAlert {
        let color: Color = switch event {
        case .pluggedIn: .green
        case .unplugged: .white
        case .low: .red
        }

        return NotchAlert(
            leading: AnyView(BatteryAlertGlyph(level: state.fraction, color: color, isPluggedIn: event == .pluggedIn)),
            duration: .seconds(event == .pluggedIn ? 3 : 2.5)
        )
    }
}

/// Jauge animée de l'alerte : elle se remplit jusqu'au niveau actuel et l'éclair apparaît.
/// Animation jouée une seule fois (aucune boucle qui consommerait du CPU).
private struct BatteryAlertGlyph: View {
    let level: Double
    let color: Color
    let isPluggedIn: Bool

    @State private var displayedLevel: Double = 0
    @State private var showsBolt = false

    var body: some View {
        BatteryGlyph(level: displayedLevel, color: color, showsBolt: showsBolt)
            .onAppear {
                displayedLevel = isPluggedIn ? 0 : level
                withAnimation(.spring(duration: 0.9, bounce: 0.1).delay(0.15)) {
                    displayedLevel = level
                }
                if isPluggedIn {
                    withAnimation(.spring(duration: 0.4, bounce: 0.5).delay(0.35)) {
                        showsBolt = true
                    }
                }
            }
    }
}

// MARK: - Vue étendue

struct BatteryExpandedView: View {
    let module: BatteryModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        if let state = module.state, size != .small {
            // Moyen ou grand : grande jauge (pourcentage inclus) à gauche, informations à droite.
            HStack(spacing: 14) {
                BatteryGlyph(state: state, isLowPowerMode: module.isLowPowerMode, size: CGSize(width: 76, height: 36))
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusText(state))
                        .font(.system(size: 13, weight: .semibold))
                    if let detail = detailText(state) {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    // Heure prévue de la charge complète.
                    if let full = state.estimatedFullDate(from: Date()) {
                        Text("Pleine vers \(full, format: .dateTime.hour().minute())")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    if module.isLowPowerMode {
                        Label("Économie d'énergie", systemImage: "leaf.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.yellow)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(12)
        } else if let state = module.state {
            // Disposition verticale : la carte est étroite (une part de largeur).
            VStack(spacing: 4) {
                // Grande jauge : le pourcentage est dedans (comme sur macOS 27).
                BatteryGlyph(state: state, isLowPowerMode: module.isLowPowerMode, size: CGSize(width: 76, height: 36))
                    .padding(.bottom, 4)
                Text(statusText(state))
                    .font(.system(size: 11, weight: .medium))
                if let detail = detailText(state) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if module.isLowPowerMode {
                    Label("Économie d'énergie", systemImage: "leaf.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.yellow)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(10)
        } else {
            VStack(spacing: 6) {
                LineGlyph(shape: PlugShape())
                    .frame(width: 26, height: 26)
                Text("Aucune batterie détectée")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
        }
    }

    private func statusText(_ state: BatteryState) -> LocalizedStringKey {
        switch state.status {
        case .charging: "En charge"
        case .charged: "Chargée"
        case .pluggedNotCharging: "Branchée, charge en pause"
        case .discharging: "Sur batterie"
        }
    }

    private func detailText(_ state: BatteryState) -> LocalizedStringKey? {
        switch state.status {
        case .charging:
            guard let minutes = state.minutesToFull else { return "Calcul du temps de charge…" }
            return "Pleine dans \(Self.format(minutes))"
        case .discharging:
            guard let minutes = state.minutesToEmpty else { return "Calcul de l'autonomie…" }
            return "\(Self.format(minutes)) restantes"
        case .charged, .pluggedNotCharging:
            return nil
        }
    }

    /// Formate une durée en minutes, ex. « 2 h 15 min ».
    private static func format(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

// MARK: - Réglages

struct BatterySettingsView: View {
    @Bindable var module: BatteryModule

    var body: some View {
        Group {
            Toggle("Toujours afficher le niveau quand l'encoche est repliée", isOn: $module.showInCompact)
            Toggle("Animation au branchement et au débranchement", isOn: $module.alertOnPowerChange)
            Toggle("Alerte de batterie faible (20 % et 10 %)", isOn: $module.lowBatteryAlert)
            Toggle("Temps restant avant la charge complète, pendant la charge", isOn: $module.chargingActivity)
        }
    }
}
