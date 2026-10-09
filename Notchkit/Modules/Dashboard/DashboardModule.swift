import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

/// Module Dashboard : raccourcis d'apps et synthèse du système, en un coup d'œil.
@MainActor
@Observable
final class DashboardModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "dashboard",
        name: "Dashboard",
        summary: "Vos apps préférées à un clic et l'état du Mac en un coup d'œil.",
        systemImage: "square.grid.2x2",
        category: .widgets,
        tier: .free,
        defaultEnabled: false
    )

    /// Apps proposées au premier lancement (seules celles qui sont installées s'affichent).
    static let defaultApps = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS",
                              "com.apple.Music", "com.apple.Notes", "com.apple.Terminal", "com.apple.dt.Xcode"]
    static let maxApps = 12

    /// Identifiants des apps, dans l'ordre d'affichage.
    var appIDs: [String] {
        didSet { UserDefaults.standard.set(appIDs, forKey: Keys.apps) }
    }

    private enum Keys {
        static let apps = "module.dashboard.apps"
    }

    init(context: ModuleContext) {
        appIDs = UserDefaults.standard.stringArray(forKey: Keys.apps) ?? Self.defaultApps
    }

    /// Apps installées parmi celles choisies.
    var apps: [(id: String, url: URL)] {
        appIDs.compactMap { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id, $0) } }
    }

    func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Choix d'une app à ajouter (fenêtre « Ouvrir » sur le dossier Applications).
    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        appIDs = Array((appIDs + ids.filter { !appIDs.contains($0) }).prefix(Self.maxApps))
    }

    func remove(_ id: String) {
        appIDs.removeAll { $0 == id }
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "square.grid.2x2", value: nil, caption: String(localized: "Dashboard")))
    }

    func expandedView() -> AnyView { AnyView(DashboardExpandedView(module: self)) }
    func settingsView() -> AnyView? { AnyView(DashboardSettingsView(module: self)) }
}

struct DashboardExpandedView: View {
    let module: DashboardModule
    @Environment(\.widgetSize) private var size
    private var sampler: SystemSampler { .shared }

    var body: some View {
        HStack(spacing: 12) {
            let columns = Array(repeating: GridItem(.fixed(34), spacing: 8), count: size == .large ? 4 : 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(module.apps.prefix(size == .large ? 8 : 6), id: \.id) { app in
                    Button { module.launch(app.url) } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help(FileManager.default.displayName(atPath: app.url.path))
                    .contextMenu {
                        Button("Retirer du Dashboard") { module.remove(app.id) }
                    }
                }
            }
            if size == .large {
                let s = sampler.snapshot
                VStack(alignment: .leading, spacing: 6) {
                    gauge("cpu", String(localized: "Processeur"), s.cpuTotal)
                    gauge("memorychip", String(localized: "Mémoire"),
                          s.memoryTotal > 0 ? Double(s.memoryUsed) / Double(s.memoryTotal) : 0)
                    gauge("internaldrive", String(localized: "Disque"),
                          s.diskTotal > 0 ? 1 - Double(s.diskFree) / Double(s.diskTotal) : 0)
                    Label(SystemMath.formattedRate(s.networkIn), systemImage: "arrow.down")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .samplesSystem()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gauge(_ symbol: String, _ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer(minLength: 4)
                Text(SystemFormat.percent(value)).monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            StandByBar(value: value, height: 4)
        }
    }
}

struct DashboardSettingsView: View {
    @Bindable var module: DashboardModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(module.apps, id: \.id) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: app.url.path))
                    Spacer()
                    Button("Retirer") { module.remove(app.id) }
                        .buttonStyle(.link)
                }
            }
            Button("Ajouter une app…", action: module.addApp)
                .disabled(module.appIDs.count >= DashboardModule.maxApps)
        }
    }
}
