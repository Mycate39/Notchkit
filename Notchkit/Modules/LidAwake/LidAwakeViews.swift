import SwiftUI

/// Valeur de l'activité repliée : le temps restant d'un maintien à durée, sinon le temps écoulé.
struct LidAwakeCompactValue: View {
    let since: Date
    let until: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(LiveActivityFormat.countdown(until.map { max(0, $0.timeIntervalSince(context.date)) }
                                              ?? context.date.timeIntervalSince(since)))
                .monospacedDigit()
                .foregroundStyle(.mint)
        }
    }
}

enum LidAwakeAlerts {
    @MainActor
    static func stopped(_ stop: LidAwakeStop) -> NotchAlert {
        let (symbol, color): (String, Color) = switch stop {
        case .battery: ("battery.25percent", .red)
        case .heat: ("thermometer.high", .orange)
        case .unplugged: ("powerplug", .orange)
        case .timer: ("timer", .mint)
        }
        return NotchAlert(
            leading: AnyView(Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)),
            duration: .seconds(5),
            expandedContent: AnyView(ScriptBanner(title: String(localized: "Le Mac peut se mettre en veille"),
                                                  message: LidAwakeText.stopReason(stop), symbol: symbol, color: color)),
            expandedSize: NotchLayout.scriptBannerSize
        )
    }
}

enum LidAwakeText {
    static func stopReason(_ stop: LidAwakeStop) -> String {
        switch stop {
        case let .battery(level): String(localized: "Batterie à \(level) %")
        case .heat: String(localized: "Le Mac chauffe capot fermé")
        case .unplugged: String(localized: "Mac débranché")
        case .timer: String(localized: "Durée écoulée")
        }
    }

    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return String(localized: "Jusqu'à l'arrêt") }
        return minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) h")
    }
}

/// Réglages : interrupteur, assistant système, agents et sécurités.
struct LidAwakeSettingsView: View {
    @Bindable var module: LidAwakeModule
    @State private var duration: Int? = nil

    var body: some View {
        Group {
            LabeledContent {
                Toggle("", isOn: Binding(get: { module.isManualOn },
                                         set: { module.setManual($0, minutes: duration) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            } label: {
                Text("Garder le Mac éveillé capot fermé")
                Text(statusText)
            }
            Picker("Durée", selection: $duration) {
                ForEach(LidAwakeSettings.durations, id: \.self) { minutes in
                    Text(LidAwakeText.duration(minutes)).tag(minutes)
                }
            }
            .disabled(module.isManualOn)

            helperRow

            Toggle("Rester éveillé tant qu'un agent travaille", isOn: $module.settings.followsAgents)
            Picker("Délai après la fin du travail", selection: $module.settings.agentQuietMinutes) {
                ForEach(LidAwakeSettings.quietDelays, id: \.self) { Text(LidAwakeText.duration($0)).tag($0) }
            }
            .disabled(!module.settings.followsAgents)

            Picker("Batterie minimale", selection: $module.settings.batteryFloor) {
                ForEach(LidAwakeSettings.batteryFloors, id: \.self) { Text(verbatim: "\($0) %").tag($0) }
            }
            Toggle("S'arrêter si le Mac est débranché", isOn: $module.settings.stopsWhenUnplugged)
            Text("Le maintien s'arrête aussi si le Mac chauffe capot fermé. À la fin, capot fermé, Notchkit met le Mac en veille ; s'il quitte ou plante, la veille normale revient d'elle-même. Évitez de ranger un Mac éveillé dans un sac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var helperRow: some View {
        LabeledContent {
            switch module.helperState {
            case .ready:
                Button("Désinstaller", action: module.uninstallHelper)
            case .outdated:
                Button("Mettre à jour…", action: module.prepareHelper)
                    .buttonStyle(.borderedProminent)
            case .notInstalled, .failed:
                Button("Installer…", action: module.prepareHelper)
            }
        } label: {
            Text("Assistant système")
            Text(helperText)
        }
        if let error = module.helperError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var helperText: String {
        switch module.helperState {
        case .ready: String(localized: "Installé")
        case .outdated: String(localized: "Une nouvelle version de l'assistant est à installer.")
        case .notInstalled, .failed:
            String(localized: "Nécessaire pour couper la veille capot fermé. macOS demandera une fois votre mot de passe administrateur.")
        }
    }

    private var statusText: String {
        if let since = module.holdingSince {
            let elapsed = ScriptActivityTracker.durationText(Date().timeIntervalSince(since))
            return module.lidClosed ? String(localized: "Éveillé capot fermé depuis \(elapsed)")
                                    : String(localized: "Actif depuis \(elapsed)")
        }
        if let stop = module.lastStop { return String(localized: "Arrêté : \(LidAwakeText.stopReason(stop))") }
        return String(localized: "Le Mac se met en veille normalement quand on ferme le capot.")
    }
}
