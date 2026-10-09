import SwiftUI

extension LiveActivity {
    /// Couleur associée : orange pour les minuteurs, bleu pour les téléchargements, violet pour les tâches.
    var tint: Color {
        if isFinished && kind != .timer { return .green }
        switch kind {
        case .timer, .stopwatch: return .orange
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
                    .foregroundStyle(activity.kind == .timer || activity.kind == .stopwatch || activity.isFinished
                                     ? activity.tint : .white)
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func value(at date: Date) -> String {
        if let elapsed = activity.elapsed(at: date) {
            return LiveActivityFormat.countdown(elapsed)
        }
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
    /// Choix d'une durée précise (molettes heures / minutes / secondes).
    @State private var isPickingDuration = false
    @State private var isPickingAlarm = false

    var body: some View {
        Group {
            if isPickingDuration {
                TimerDurationPicker(module: module, isPresented: $isPickingDuration)
            } else if isPickingAlarm {
                AlarmPicker(module: module, isPresented: $isPickingAlarm)
            } else if module.activities.count == 1, let timer = module.activities.first, timer.kind == .timer {
                // Un seul minuteur : présentation « Dynamic Island » d'iOS.
                TimerHeroView(module: module, timer: timer, compact: size == .small)
            } else {
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
            }
        }
        .padding(10)
        .animation(.snappy(duration: 0.25), value: isPickingDuration)
    }

    /// Lancement rapide d'un minuteur (durées, durée précise), chronomètre, alarme et Pomodoro.
    /// La rangée garde autant de durées que la place le permet, sans jamais tronquer un libellé.
    private var timerLauncher: some View {
        ViewThatFits(in: .horizontal) {
            launcherRow(presets: LiveActivitiesModule.presets, extras: true)
            launcherRow(presets: [5, 25], extras: true)
            launcherRow(presets: [5], extras: true)
            launcherRow(presets: [5], extras: false)
        }
    }

    private func launcherRow(presets: [Int], extras: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
            ForEach(presets, id: \.self) { minutes in
                Button("\(minutes) min") { module.startTimer(minutes: Double(minutes)) }
                    .buttonStyle(.standBy(.small))
                    .fixedSize()
            }
            Button { isPickingDuration = true } label: {
                Image(systemName: "plus")
            }
            .help("Choisir une durée précise")
            if extras {
                Spacer(minLength: 6)
                Button(action: module.startStopwatch) { Image(systemName: "stopwatch") }
                    .help("Chronomètre")
                Button { isPickingAlarm = true } label: { Image(systemName: "alarm") }
                    .help("Alarme")
                Button(action: module.startPomodoro) { Image(systemName: "brain.head.profile") }
                    .help("Pomodoro (25 min de travail, 5 min de pause)")
            }
        }
        .buttonStyle(.standBy(.small, circle: true))
    }
}

// MARK: - Minuteur façon iOS

/// Minuteur en cours, présenté comme dans la Dynamic Island d'iOS :
/// boutons ronds à gauche, grand décompte ambre à droite.
private struct TimerHeroView: View {
    let module: LiveActivitiesModule
    let timer: LiveActivity
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 14) {
            HStack(spacing: 8) {
                if timer.isFinished {
                    RoundButton(symbol: "arrow.counterclockwise", isActive: true, compact: compact) {
                        module.remove(timer.id)
                        module.startTimer(seconds: timer.duration, title: timer.title)
                    }
                    .help("Relancer")
                } else {
                    RoundButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", isActive: true, compact: compact) {
                        module.togglePause(timer.id)
                    }
                    .help(timer.isPaused ? "Reprendre" : "Pause")
                }
                RoundButton(symbol: "xmark", isActive: false, compact: compact) {
                    module.remove(timer.id)
                }
                .help("Arrêter")
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(timer.isFinished ? "Terminé" : (timer.isPaused ? "En pause" : "Minuteur"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(LiveActivityFormat.countdown(timer.remaining(at: context.date) ?? 0))
                        .font(.system(size: compact ? 28 : 40, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tint.opacity(timer.isPaused ? 0.6 : 1))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: timer.remaining(at: context.date))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Ajouter une minute") { module.extend(timer.id, by: 60) }
            Button("Ajouter cinq minutes") { module.extend(timer.id, by: 300) }
        }
    }
}

/// Bouton rond StandBy : ambre pour l'action principale, gris sombre pour arrêter.
private struct RoundButton: View {
    let symbol: String
    let isActive: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .fontWeight(.bold)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.standBy(compact ? .regular : .large, active: isActive, circle: true))
    }
}

/// Choix d'une durée précise avec trois molettes (heures, minutes, secondes), comme l'app Horloge.
private struct TimerDurationPicker: View {
    let module: LiveActivitiesModule
    @Binding var isPresented: Bool

    @AppStorage("module.activities.lastHours") private var hours = 0
    @AppStorage("module.activities.lastMinutes") private var minutes = 10
    @AppStorage("module.activities.lastSeconds") private var seconds = 0

    private var total: Int { hours * 3600 + minutes * 60 + seconds }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                WheelPicker(value: $hours, range: 0...23, unit: "h")
                WheelPicker(value: $minutes, range: 0...59, unit: "min")
                WheelPicker(value: $seconds, range: 0...59, unit: "s")
            }
            HStack {
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.standBy(.small))
                Spacer()
                Button {
                    module.startTimer(seconds: TimeInterval(total))
                    isPresented = false
                } label: {
                    Label("Démarrer", systemImage: "play.fill")
                }
                .buttonStyle(.standBy(.small, active: true))
                .disabled(total == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Choix de l'heure d'une alarme (molettes heures / minutes).
private struct AlarmPicker: View {
    let module: LiveActivitiesModule
    @Binding var isPresented: Bool

    @AppStorage("module.activities.alarmHour") private var hour = 7
    @AppStorage("module.activities.alarmMinute") private var minute = 30

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "alarm").foregroundStyle(.tint)
                WheelPicker(value: $hour, range: 0...23, unit: "h")
                WheelPicker(value: $minute, range: 0...59, unit: "min")
            }
            HStack {
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.standBy(.small))
                Spacer()
                Button {
                    module.startAlarm(hour: hour, minute: minute)
                    isPresented = false
                } label: {
                    Label("Régler l'alarme", systemImage: "alarm")
                }
                .buttonStyle(.standBy(.small, active: true))
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Molette à défilement : la valeur sélectionnée s'aligne au centre, sur un bandeau gris.
/// Défilement au trackpad ou à la souris, clic sur une valeur pour la choisir.
private struct WheelPicker: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    private let rowHeight: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(height: rowHeight)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { number in
                        Text("\(number)")
                            .font(.system(size: 17, weight: number == value ? .semibold : .regular, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(number == value ? .white : .white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 34)
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.snappy) { value = number } }
                            .id(number)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, rowHeight, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding(get: { value }, set: { if let new = $0 { value = new } }), anchor: .center)
            .scrollIndicators(.never)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )

            Text(unit)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
        .frame(height: rowHeight * 3)
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
        HStack(spacing: 6) {
            if activity.kind == .stopwatch {
                Button { module.togglePause(activity.id) } label: {
                    Image(systemName: activity.isPaused ? "play.fill" : "pause.fill")
                }
                .help(activity.isPaused ? "Reprendre" : "Pause")
            }
            if activity.kind == .timer {
                Button { module.extend(activity.id, by: 60) } label: {
                    Text("+1")
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
        .buttonStyle(.standBy(.small, circle: true))
    }

    private func subtitle(at date: Date) -> String {
        switch activity.kind {
        case .stopwatch:
            let elapsed = LiveActivityFormat.countdown(activity.elapsed(at: date) ?? 0)
            return activity.isPaused ? String(localized: "En pause · \(elapsed)") : elapsed
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

/// Version mini : l'activité la plus importante, ou un lancement rapide de minuteur.
struct LiveActivitiesMiniView: View {
    let module: LiveActivitiesModule

    var body: some View {
        if let activity = module.mostRelevant {
            GeometryReader { proxy in
                let side = min(proxy.size.width * 0.7, proxy.size.height * 0.5)
                VStack(spacing: proxy.size.height * 0.05) {
                    ActivityRing(activity: activity, size: side)
                    ActivityCompactValue(activity: activity, extraCount: 0)
                        .font(.system(size: max(9, side * 0.38), weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                Button("5 min") { module.startTimer(minutes: 5) }
                    .buttonStyle(.standBy(.small, active: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
