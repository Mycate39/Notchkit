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

/// Icône de batterie dessinée à la main : contour, remplissage proportionnel et éclair si branchée.
struct BatteryGlyph: View {
    var level: Double
    var color: Color
    var showsBolt: Bool
    var size = CGSize(width: 24, height: 11.5)

    init(level: Double, color: Color, showsBolt: Bool, size: CGSize = CGSize(width: 24, height: 11.5)) {
        self.level = level
        self.color = color
        self.showsBolt = showsBolt
        self.size = size
    }

    init(state: BatteryState, isLowPowerMode: Bool, size: CGSize = CGSize(width: 24, height: 11.5)) {
        self.init(
            level: state.fraction,
            color: BatteryStyle.fillColor(for: state, isLowPowerMode: isLowPowerMode),
            showsBolt: state.isPluggedIn,
            size: size
        )
    }

    var body: some View {
        let radius = size.height * 0.3
        let inset = max(1.5, size.height * 0.14)

        HStack(spacing: size.width * 0.04) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: max(1, size.height * 0.08))
                RoundedRectangle(cornerRadius: max(0, radius - inset * 0.6), style: .continuous)
                    .fill(color)
                    .frame(width: max(0, (size.width - inset * 2) * min(max(level, 0), 1)))
                    .padding(inset)
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                if showsBolt {
                    // Éclair au trait, cerné de noir pour rester lisible sur la jauge.
                    ZStack {
                        LineGlyph(shape: BoltShape(), weight: 0.22).foregroundStyle(.black.opacity(0.55))
                        LineGlyph(shape: BoltShape(), weight: 0.11).foregroundStyle(.white)
                    }
                    .frame(width: size.height * 1.05, height: size.height * 1.05)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Borne de la batterie
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.45))
                .frame(width: max(1.5, size.width * 0.06), height: size.height * 0.38)
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
            trailing: AnyView(
                Text("\(state.level) %")
                    .monospacedDigit()
                    .foregroundStyle(color)
            ),
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
            // Moyen ou grand : jauge à gauche, informations à droite.
            HStack(spacing: 14) {
                BatteryGlyph(state: state, isLowPowerMode: module.isLowPowerMode, size: CGSize(width: 54, height: 26))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.level) %")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(BatteryStyle.textColor(for: state, isLowPowerMode: module.isLowPowerMode))
                    Text(statusText(state))
                        .font(.system(size: 12, weight: .medium))
                    if let detail = detailText(state) {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
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
                BatteryGlyph(state: state, isLowPowerMode: module.isLowPowerMode, size: CGSize(width: 46, height: 22))
                    .padding(.bottom, 2)
                Text("\(state.level) %")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BatteryStyle.textColor(for: state, isLowPowerMode: module.isLowPowerMode))
                Text(statusText(state))
                    .font(.system(size: 11, weight: .medium))
                if let detail = detailText(state) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if module.isLowPowerMode {
                    Label("Économie d'énergie", systemImage: "leaf.fill")
                        .font(.system(size: 9, weight: .medium))
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
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Toujours afficher le niveau quand l'encoche est repliée", isOn: $module.showInCompact)
            Toggle("Animation au branchement et au débranchement", isOn: $module.alertOnPowerChange)
            Toggle("Alerte de batterie faible (20 % et 10 %)", isOn: $module.lowBatteryAlert)
        }
    }
}
