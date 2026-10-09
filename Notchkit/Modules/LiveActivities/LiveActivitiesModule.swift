import AppKit
import SwiftUI
import Observation

/// Module Activités live : minuteurs, téléchargements et tâches externes, plusieurs à la fois.
@MainActor
@Observable
final class LiveActivitiesModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "activities",
        name: "Activités live",
        summary: "Minuteurs, téléchargements en cours et progression de tâches, plusieurs à la fois.",
        systemImage: "timer",
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    /// Durées proposées pour lancer un minuteur d'un clic (minutes).
    static let presets = [1, 5, 15, 25]
    /// Un minuteur terminé reste affiché (et « sonne » dans l'encoche) pendant ce délai.
    static let ringingDuration: TimeInterval = 30

    private(set) var activities: [LiveActivity] = []

    // MARK: Réglages du module

    var playSound: Bool {
        didSet { UserDefaults.standard.set(playSound, forKey: Keys.playSound) }
    }
    /// Suivi des téléchargements (demande l'accès au dossier Téléchargements).
    var trackDownloads: Bool {
        didSet {
            UserDefaults.standard.set(trackDownloads, forKey: Keys.trackDownloads)
            guard isStarted else { return }
            trackDownloads ? downloads.start() : stopDownloads()
        }
    }

    private enum Keys {
        static let playSound = "module.activities.playSound"
        static let trackDownloads = "module.activities.trackDownloads"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let downloads = DownloadsMonitor()
    @ObservationIgnored private var timerTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var cleanupTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var isStarted = false

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        playSound = defaults.object(forKey: Keys.playSound) as? Bool ?? true
        trackDownloads = defaults.object(forKey: Keys.trackDownloads) as? Bool ?? false
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true
        downloads.onUpdate = { [weak self] list in self?.updateDownloads(list) }
        downloads.onFinished = { [weak self] url in self?.downloadFinished(url) }
        if trackDownloads { downloads.start() }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        downloads.stop()
        timerTasks.values.forEach { $0.cancel() }
        cleanupTasks.values.forEach { $0.cancel() }
        timerTasks.removeAll()
        cleanupTasks.removeAll()
        activities.removeAll()
    }

    // MARK: Minuteurs

    func startTimer(minutes: Double, title: String? = nil) {
        startTimer(seconds: minutes * 60, title: title)
    }

    func startTimer(seconds: TimeInterval, title: String? = nil) {
        let timer = LiveActivity.timer(duration: seconds, title: title)
        withAnimation(.snappy) { activities.append(timer) }
        scheduleCompletion(of: timer)
    }

    // MARK: Chronomètre, alarme, Pomodoro

    func startStopwatch() {
        withAnimation(.snappy) { activities.append(.stopwatch()) }
    }

    func startAlarm(hour: Int, minute: Int) {
        let alarm = LiveActivity.alarm(hour: hour, minute: minute)
        withAnimation(.snappy) { activities.append(alarm) }
        scheduleCompletion(of: alarm)
    }

    func startPomodoro() {
        let pomodoro = LiveActivity.pomodoro(.work)
        withAnimation(.snappy) { activities.append(pomodoro) }
        scheduleCompletion(of: pomodoro)
    }

    func togglePause(_ id: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if activities[index].kind == .stopwatch {
            var watch = activities[index]
            if let start = watch.startDate {
                watch.elapsedBase += Date().timeIntervalSince(start)
                watch.startDate = nil
            } else {
                watch.startDate = Date()
            }
            activities[index] = watch
            return
        }
        guard activities[index].kind == .timer else { return }
        var timer = activities[index]
        if let remaining = timer.pausedRemaining {
            timer.pausedRemaining = nil
            timer.endDate = Date().addingTimeInterval(remaining)
            activities[index] = timer
            scheduleCompletion(of: timer)
        } else {
            timer.pausedRemaining = timer.remaining()
            timer.endDate = nil
            activities[index] = timer
            timerTasks.removeValue(forKey: id)?.cancel()
        }
    }

    /// Ajoute du temps à un minuteur (ex. +1 min).
    func extend(_ id: String, by seconds: TimeInterval) {
        guard let index = activities.firstIndex(where: { $0.id == id }), activities[index].kind == .timer else { return }
        var timer = activities[index]
        timer.duration += seconds
        if timer.isFinished {
            timer.isFinished = false
            timer.finishedAt = nil
            timer.endDate = Date().addingTimeInterval(seconds)
            cleanupTasks.removeValue(forKey: id)?.cancel()
        } else if let paused = timer.pausedRemaining {
            timer.pausedRemaining = paused + seconds
        } else {
            timer.endDate = timer.endDate?.addingTimeInterval(seconds)
        }
        activities[index] = timer
        if !timer.isPaused { scheduleCompletion(of: timer) }
    }

    func remove(_ id: String) {
        timerTasks.removeValue(forKey: id)?.cancel()
        cleanupTasks.removeValue(forKey: id)?.cancel()
        withAnimation(.snappy) { activities.removeAll { $0.id == id } }
    }

    private func scheduleCompletion(of timer: LiveActivity) {
        timerTasks.removeValue(forKey: timer.id)?.cancel()
        guard let endDate = timer.endDate else { return }
        timerTasks[timer.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endDate.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.timerFinished(timer.id)
        }
    }

    private func timerFinished(_ id: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        // Pomodoro : la phase suivante démarre aussitôt (travail ↔ pause).
        if let phase = activities[index].pomodoro {
            let (next, count) = PomodoroPlan.next(after: phase, count: activities[index].pomodoroCount)
            var following = LiveActivity.pomodoro(next, count: count)
            timerTasks[id] = nil
            if playSound { NSSound(named: "Glass")?.play() }
            withAnimation(.snappy) { activities[index] = following }
            context.presentAlert(LiveActivityAlerts.pomodoroPhase(next))
            scheduleCompletion(of: following)
            return
        }
        activities[index].isFinished = true
        activities[index].finishedAt = Date()
        timerTasks[id] = nil
        if playSound { NSSound(named: "Glass")?.play() }
        context.presentAlert(LiveActivityAlerts.timerFinished(activities[index]))
        removeLater(id, after: Self.ringingDuration)
    }

    // MARK: Téléchargements

    private func stopDownloads() {
        downloads.stop()
        withAnimation(.snappy) { activities.removeAll { $0.kind == .download && !$0.isFinished } }
    }

    private func updateDownloads(_ list: [DownloadsMonitor.Download]) {
        let ids = Set(list.map { "download-\($0.temporaryURL.path)" })
        var updated = activities.filter { $0.kind != .download || $0.isFinished || ids.contains($0.id) }
        for download in list {
            let id = "download-\(download.temporaryURL.path)"
            var activity = updated.first { $0.id == id }
                ?? LiveActivity(id: id, kind: .download, title: download.name, symbol: "arrow.down.circle")
            activity.title = download.name
            activity.progress = download.total.map { Double(download.bytes) / Double($0) }
            activity.detail = download.total.map {
                "\(DownloadFiles.formattedSize(download.bytes)) / \(DownloadFiles.formattedSize($0))"
            } ?? DownloadFiles.formattedSize(download.bytes)
            if let index = updated.firstIndex(where: { $0.id == id }) {
                updated[index] = activity
            } else {
                updated.append(activity)
            }
        }
        if updated != activities { activities = updated }
    }

    private func downloadFinished(_ url: URL) {
        let id = "download-done-\(url.path)"
        guard !activities.contains(where: { $0.id == id }) else { return }
        let activity = LiveActivity(
            id: id, kind: .download, title: url.lastPathComponent, symbol: "checkmark.circle.fill",
            detail: String(localized: "Téléchargement terminé"), fileURL: url, isFinished: true, finishedAt: Date()
        )
        withAnimation(.snappy) { activities.append(activity) }
        context.presentAlert(LiveActivityAlerts.downloadFinished())
        removeLater(id, after: 60)
    }

    func reveal(_ activity: LiveActivity) {
        guard let url = activity.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Commandes externes

    /// Traite un lien `notchkit://…` (scripts, raccourcis, autres apps).
    func handle(_ command: LiveActivityCommand) {
        switch command {
        case let .startTimer(seconds, title):
            startTimer(seconds: seconds, title: title)
        case let .update(id, title, progress, symbol, detail):
            let key = "task-\(id)"
            var activity = activities.first { $0.id == key }
                ?? LiveActivity(id: key, kind: .task, title: title ?? id, symbol: symbol ?? "gearshape.2")
            if let title { activity.title = title }
            if let symbol { activity.symbol = symbol }
            if let detail { activity.detail = detail }
            activity.progress = progress ?? activity.progress
            activity.isFinished = false
            cleanupTasks.removeValue(forKey: key)?.cancel()
            if let index = activities.firstIndex(where: { $0.id == key }) {
                activities[index] = activity
            } else {
                withAnimation(.snappy) { activities.append(activity) }
            }
        case let .end(id):
            let key = "task-\(id)"
            guard let index = activities.firstIndex(where: { $0.id == key }) else { return }
            activities[index].isFinished = true
            activities[index].progress = 1
            activities[index].finishedAt = Date()
            removeLater(key, after: 4)
        }
    }

    private func removeLater(_ id: String, after seconds: TimeInterval) {
        cleanupTasks.removeValue(forKey: id)?.cancel()
        cleanupTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.cleanupTasks[id] = nil
            self?.remove(id)
        }
    }

    // MARK: Affichage

    var mostRelevant: LiveActivity? { LiveActivityRanking.mostRelevant(activities) }

    var compactPriority: ModulePriority {
        guard let activity = mostRelevant else { return .none }
        if activity.kind == .timer && activity.isFinished { return .high }
        return activity.isFinished ? .low : .normal
    }

    var expandedWidthWeight: CGFloat { 2 }

    func compactLeading() -> AnyView? {
        guard let activity = mostRelevant else { return nil }
        // Minuteur : icône orange, comme dans la Dynamic Island d'iOS.
        if activity.kind == .timer || activity.kind == .stopwatch {
            return AnyView(
                Image(systemName: activity.isPaused ? "pause.circle.fill" : activity.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .contentTransition(.symbolEffect(.replace))
            )
        }
        return AnyView(ActivityRing(activity: activity, size: 18))
    }

    func compactTrailing() -> AnyView? {
        guard let activity = mostRelevant else { return nil }
        return AnyView(ActivityCompactValue(activity: activity, extraCount: activities.filter { !$0.isFinished }.count - 1))
    }

    func miniView() -> AnyView {
        AnyView(LiveActivitiesMiniView(module: self))
    }

    func expandedView() -> AnyView {
        AnyView(LiveActivitiesExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(LiveActivitiesSettingsView(module: self))
    }
}

enum LiveActivityAlerts {
    @MainActor
    static func timerFinished(_ timer: LiveActivity) -> NotchAlert {
        NotchAlert(
            leading: AnyView(RingingBell()),
            trailing: AnyView(Text("Terminé").foregroundStyle(.orange)),
            duration: .seconds(5)
        )
    }

    @MainActor
    static func pomodoroPhase(_ phase: LiveActivity.PomodoroPhase) -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: phase == .work ? "brain.head.profile" : "cup.and.saucer.fill")
                .foregroundStyle(.orange)),
            trailing: AnyView(Text(phase == .work ? "Au travail" : "Pause").foregroundStyle(.orange)),
            duration: .seconds(4)
        )
    }

    @MainActor
    static func downloadFinished() -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)),
            trailing: AnyView(Image(systemName: "checkmark").foregroundStyle(.green)),
            duration: .seconds(2.5)
        )
    }
}

/// Cloche qui s'agite trois fois (compatible macOS 14).
private struct RingingBell: View {
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "bell.fill")
            .foregroundStyle(.orange)
            .rotationEffect(.degrees(angle), anchor: .top)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.12).repeatCount(9, autoreverses: true)) { angle = 18 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.easeOut(duration: 0.15)) { angle = 0 } }
            }
    }
}
