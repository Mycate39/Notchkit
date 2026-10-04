import SwiftUI

extension LiveActivity {
    /// Couleur associée : orange pour les minuteurs, bleu pour les téléchargements, violet pour les tâches.
    var tint: Color {
        if isFinished && kind != .timer { return .green }
        switch kind {
        case .timer: return .orange
        case .download: return .blue
        case .task: return .purple
        }
    }
}

/// Anneau de progression avec l'icône de l'activité au centre.
struct ActivityRing: View {
    let activity: LiveActivity
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = activity.fraction(at: context.date)
            ZStack {
                Circle().stroke(activity.tint.opacity(0.25), lineWidth: size * 0.11)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(activity.tint, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: fraction)
                } else {
                    // Progression inconnue : arc qui tourne.
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(activity.tint, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180))
                }
                Image(systemName: activity.symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(activity.tint)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Valeur affichée à droite de l'encoche repliée : temps restant, pourcentage ou taille.
struct ActivityCompactValue: View {
    let activity: LiveActivity
    let extraCount: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 3) {
                Text(value(at: context.date))
                    .monospacedDigit()
                    .foregroundStyle(activity.isFinished ? activity.tint : .white)
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func value(at date: Date) -> String {
        if let remaining = activity.remaining(at: date) {
            return activity.isFinished ? String(localized: "0:00") : LiveActivityFormat.countdown(remaining)
        }
        if let fraction = activity.fraction(at: date) {
            return fraction.formatted(.percent.precision(.fractionLength(0)))
        }
        return activity.detail ?? ""
    }
}

enum LiveActivityFormat {
    /// « 4:32 » ou « 1:04:32 ».
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let pattern: Duration.TimeFormatStyle.Pattern = total >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(total).formatted(.time(pattern: pattern))
    }
}

// MARK: - Carte dans l'encoche dépliée

struct LiveActivitiesExpandedView: View {
    let module: LiveActivitiesModule
    @Environment(\.widgetSize) private var size
    @State private var customMinutes = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if module.activities.isEmpty {
                Text("Aucune activité en cours")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(module.activities) { activity in
                            ActivityRow(module: module, activity: activity, compact: size == .small)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            timerLauncher
        }
        .padding(10)
    }

    /// Lancement rapide d'un minuteur.
    private var timerLauncher: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
            ForEach(size == .small ? [5, 25] : LiveActivitiesModule.presets, id: \.self) { minutes in
                Button("\(minutes) min") { module.startTimer(minutes: Double(minutes)) }
                    .buttonStyle(ChipButtonStyle())
            }
            if size != .small {
                Menu {
                    ForEach([2, 3, 10, 20, 30, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes) min") { module.startTimer(minutes: Double(minutes)) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Autre durée")
            }
        }
    }
}

private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(configuration.isPressed ? 0.25 : 0.12), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct ActivityRow: View {
    let module: LiveActivitiesModule
    let activity: LiveActivity
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            ActivityRing(activity: activity, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(subtitle(at: context.date))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(activity.isFinished ? activity.tint : .white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if !compact { controls }
        }
        .contentShape(Rectangle())
        .onTapGesture { if activity.fileURL != nil { module.reveal(activity) } }
        .contextMenu {
            if activity.fileURL != nil { Button("Afficher dans le Finder") { module.reveal(activity) } }
            Button(activity.isFinished ? "Retirer" : "Arrêter") { module.remove(activity.id) }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if activity.kind == .timer {
                Button { module.extend(activity.id, by: 60) } label: {
                    Text("+1").font(.system(size: 9, weight: .bold))
                }
                .help("Ajouter une minute")
                if !activity.isFinished {
                    Button { module.togglePause(activity.id) } label: {
                        Image(systemName: activity.isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(activity.isPaused ? "Reprendre" : "Pause")
                }
            }
            if activity.kind != .download || activity.isFinished {
                Button { module.remove(activity.id) } label: {
                    Image(systemName: "xmark")
                }
                .help(activity.isFinished ? "Retirer" : "Arrêter")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.75))
    }

    private func subtitle(at date: Date) -> String {
        switch activity.kind {
        case .timer:
            if activity.isFinished { return String(localized: "Terminé") }
            let remaining = LiveActivityFormat.countdown(activity.remaining(at: date) ?? 0)
            return activity.isPaused ? String(localized: "En pause · \(remaining)") : remaining
        case .download, .task:
            var parts: [String] = []
            if let fraction = activity.fraction(at: date), !activity.isFinished {
                parts.append(fraction.formatted(.percent.precision(.fractionLength(0))))
            }
            if let detail = activity.detail { parts.append(detail) }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Réglages

struct LiveActivitiesSettingsView: View {
    @Bindable var module: LiveActivitiesModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Son à la fin d'un minuteur", isOn: $module.playSound)
            Toggle("Suivre les téléchargements", isOn: $module.trackDownloads)
            Text("Affiche la progression des téléchargements de Brave, Chrome, Safari et Firefox. macOS demande l'accès au dossier Téléchargements la première fois.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Scripts et apps peuvent afficher une progression avec un lien, par exemple :\nopen \"notchkit://activity/update?id=build&title=Compilation&progress=40\"\nopen \"notchkit://activity/end?id=build\"\nopen \"notchkit://timer/start?minutes=5&title=Thé\"")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
