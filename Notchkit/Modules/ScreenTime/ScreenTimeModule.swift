import AppKit
import SwiftUI
import Observation

/// Module Temps d'écran : temps passé par app aujourd'hui, mesuré par Notchkit lui-même.
/// 100 % local : rien ne quitte le Mac (fichier dans Application Support, 30 jours au plus).
@MainActor
@Observable
final class ScreenTimeModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "screentime",
        name: "Temps d'écran",
        summary: "Le temps passé sur le Mac et dans chaque app, mesuré sur ce Mac uniquement.",
        systemImage: "hourglass",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    /// Intervalle des relevés (secondes).
    static let tick: TimeInterval = 30

    private(set) var log = ScreenTimeLog()

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastSave = Date.distantPast

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit/ScreenTime.json")
    }

    init(context: ModuleContext) {
        if let data = try? Data(contentsOf: Self.fileURL),
           let stored = try? JSONDecoder().decode(ScreenTimeLog.self, from: data) {
            log = stored
        }
    }

    func start() {
        guard loop == nil, !AutomatedRun.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tick))
                self?.record()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        save()
    }

    private func record() {
        guard ActivityClock.isActive(idle: ActivityClock.secondsSinceLastInput),
              let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return }
        log.add(Self.tick, app: app, day: ActivityClock.dayKey(Date()))
        // Écriture au plus toutes les 5 minutes (et à l'arrêt).
        if Date().timeIntervalSince(lastSave) > 300 { save() }
    }

    private func save() {
        log.prune()
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(log) { try? data.write(to: url, options: .atomic) }
        lastSave = Date()
    }

    var today: String { ActivityClock.dayKey(Date()) }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "hourglass", value: ScreenTimeFormat.duration(log.total(day: today)),
                           caption: String(localized: "Temps d'écran")))
    }

    func expandedView() -> AnyView { AnyView(ScreenTimeExpandedView(module: self)) }
}

enum ScreenTimeFormat {
    /// « 3 h 25 » ou « 42 min ».
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? String(format: "%d h %02d", minutes / 60, minutes % 60) : "\(minutes) min"
    }
}

struct ScreenTimeExpandedView: View {
    let module: ScreenTimeModule

    var body: some View {
        let day = module.today
        let total = module.log.total(day: day)
        let top = module.log.topApps(day: day, limit: 4)

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ScreenTimeFormat.duration(total))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tint)
                Text("aujourd'hui")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 5) {
                if top.isEmpty {
                    Text("Le temps d'écran apparaîtra ici au fil de la journée.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                ForEach(top, id: \.app) { entry in
                    AppUsageRow(bundleID: entry.app, seconds: entry.seconds, fraction: total > 0 ? entry.seconds / total : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct AppUsageRow: View {
    let bundleID: String
    let seconds: Double
    let fraction: Double

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 14, height: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(ScreenTimeFormat.duration(seconds)).monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                StandByBar(value: fraction, height: 3)
            }
        }
    }
}
