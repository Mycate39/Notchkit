import SwiftUI

/// Icône de l'activité repliée : le symbole choisi, cerclé de l'avancement s'il est connu.
struct ScriptCompactIcon: View {
    let activity: ScriptActivity

    var body: some View {
        ZStack {
            if let progress = activity.progress {
                Circle().stroke(activity.color.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(activity.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(NotchLayout.selectionSpring, value: progress)
                Image(systemName: activity.symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(activity.color)
            } else {
                Image(systemName: activity.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activity.color)
                    .symbolEffect(.pulse, isActive: !NotchAccessibility.reduceMotion)
            }
        }
        .frame(width: 18, height: 18)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(Text(activity.title))
    }
}

/// Valeur de l'activité repliée : l'avancement en pourcentage, sinon le temps écoulé.
struct ScriptCompactValue: View {
    let activity: ScriptActivity
    let extraCount: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 3) {
                Text(activity.progress.map { $0.formatted(.percent.precision(.fractionLength(0))) }
                     ?? LiveActivityFormat.countdown(context.date.timeIntervalSince(activity.startedAt)))
                    .monospacedDigit()
                    .foregroundStyle(activity.color)
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

/// Bannière sous l'encoche : titre et message d'une notification ou d'une fin d'activité.
struct ScriptBanner: View {
    let title: String
    let message: String?
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            // Deux lignes au plus pour le titre, une pour le message : la bannière garde sa taille.
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ScriptAlerts {
    @MainActor
    static func notification(title: String, message: String?, symbol: String, color: Color) -> NotchAlert {
        var alert = NotchAlert(
            leading: AnyView(Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)),
            duration: .seconds(4),
            expandedContent: AnyView(ScriptBanner(title: title, message: message, symbol: symbol, color: color)),
            expandedSize: NotchLayout.scriptBannerSize
        )
        alert.openModuleID = ScriptsModule.descriptor.id
        return alert
    }

    @MainActor
    static func finished(title: String, message: String?, succeeded: Bool, duration: TimeInterval?) -> NotchAlert {
        let color: Color = succeeded ? .green : .red
        let symbol = succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
        let detail = [message, duration.map(ScriptActivityTracker.durationText)].compactMap { $0 }.joined(separator: " · ")
        return NotchAlert(
            leading: AnyView(Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)),
            duration: .seconds(succeeded ? 3.5 : 6),
            expandedContent: AnyView(ScriptBanner(title: title, message: detail.isEmpty ? nil : detail,
                                                  symbol: symbol, color: color)),
            expandedSize: NotchLayout.scriptBannerSize
        )
    }
}

/// Page ouverte pendant une activité : la liste des activités en cours.
struct ScriptsExpandedView: View {
    let module: ScriptsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.tracker.ordered.isEmpty {
                Text("Aucune commande en cours.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            ForEach(module.tracker.ordered.prefix(4)) { activity in
                HStack(spacing: 8) {
                    ScriptCompactIcon(activity: activity)
                    Text(activity.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ScriptCompactValue(activity: activity, extraCount: 0)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Réglages : installation de la commande et exemples.
struct ScriptsSettingsView: View {
    @Bindable var module: ScriptsModule

    var body: some View {
        Group {
            LabeledContent {
                switch module.installStatus {
                case .installed:
                    Button("Désinstaller", action: module.uninstallCommand)
                case .outdated:
                    Button("Mettre à jour la commande", action: module.installCommand)
                case .notInstalled:
                    Button("Installer la commande", action: module.installCommand)
                        .buttonStyle(.borderedProminent)
                }
            } label: {
                Text("Commande notchkit")
                Text(statusText)
            }
            if let message = module.installerMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if case let .failed(reason) = module.serverState {
                Text("Le serveur local n'a pas pu démarrer sur le port \(String(module.port)) : \(reason)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Exemples")
                    .font(.caption.weight(.semibold))
                Text(verbatim: """
                notchkit run npm test
                notchkit notify "Deploy finished" "api is live" --color green
                notchkit start export "Export"; notchkit progress export 40; notchkit end export
                """)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                Text("« run » affiche la commande pendant qu'elle tourne, puis une coche verte ou une croix rouge avec sa durée. Lancez notchkit --help pour toutes les options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { module.refreshInstallState() }
    }

    private var statusText: String {
        switch module.installStatus {
        case let .installed(link): String(localized: "Installée dans \(link.deletingLastPathComponent().path)")
        case .outdated: String(localized: "Mise à jour nécessaire")
        case .notInstalled: String(localized: "Non installée")
        }
    }
}
