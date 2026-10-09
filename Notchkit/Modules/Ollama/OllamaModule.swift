import AppKit
import SwiftUI
import Observation

/// Modèle chargé en mémoire par Ollama.
struct OllamaModel: Identifiable, Equatable, Sendable {
    let name: String
    let size: Int64
    let sizeVRAM: Int64
    let expiresAt: Date?
    var id: String { name }
}

/// Lecture des réponses de l'API locale d'Ollama (logique pure, testée).
enum OllamaAPI {
    static let base = URL(string: "http://127.0.0.1:11434")!

    static func runningModels(from data: Data) -> [OllamaModel] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return models.compactMap { model in
            guard let name = model["name"] as? String else { return nil }
            let expires = (model["expires_at"] as? String).flatMap { dates.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return OllamaModel(name: name, size: (model["size"] as? NSNumber)?.int64Value ?? 0,
                               sizeVRAM: (model["size_vram"] as? NSNumber)?.int64Value ?? 0, expiresAt: expires)
        }
    }

    static func installedCount(from data: Data) -> Int {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (json?["models"] as? [Any])?.count ?? 0
    }
}

/// Module Ollama : état du serveur local d'IA, modèles chargés en mémoire et modèles installés.
@MainActor
@Observable
final class OllamaModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "ollama",
        name: "Ollama",
        summary: "Le serveur d'IA local : modèles chargés en mémoire et modèles installés.",
        systemImage: "cpu",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    static let interval: TimeInterval = 10

    private(set) var isRunning = false
    private(set) var loaded: [OllamaModel] = []
    private(set) var installed = 0

    @ObservationIgnored private var loop: Task<Void, Never>?

    init(context: ModuleContext) {}

    func start() {
        guard loop == nil, !AutomatedRun.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func fetch(_ path: String) async -> Data? {
        var request = URLRequest(url: OllamaAPI.base.appendingPathComponent(path))
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    func refresh() async {
        guard let running = await fetch("api/ps") else {
            if isRunning { withAnimation(.snappy) { isRunning = false; loaded = [] } }
            return
        }
        let models = OllamaAPI.runningModels(from: running)
        let count = await fetch("api/tags").map(OllamaAPI.installedCount) ?? installed
        if !isRunning || models != loaded || count != installed {
            withAnimation(.snappy) {
                isRunning = true
                loaded = models
                installed = count
            }
        }
    }

    // Modèle en mémoire : petite activité dans l'encoche repliée.
    var compactPriority: ModulePriority { loaded.isEmpty ? .none : .low }

    func compactLeading() -> AnyView? {
        guard !loaded.isEmpty else { return nil }
        return AnyView(Image(systemName: "cpu").foregroundStyle(StandBy.amber))
    }

    func compactTrailing() -> AnyView? {
        guard let first = loaded.first else { return nil }
        return AnyView(Text(first.name.components(separatedBy: ":").first ?? first.name).lineLimit(1))
    }

    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "cpu", value: isRunning ? "\(loaded.count)" : nil,
                           caption: String(localized: "Ollama")))
    }

    func expandedView() -> AnyView { AnyView(OllamaExpandedView(module: self)) }
}

struct OllamaExpandedView: View {
    let module: OllamaModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(module.isRunning ? Color.green : Color.white.opacity(0.3)).frame(width: 7, height: 7)
                Text(module.isRunning ? "Ollama en marche" : "Ollama arrêté")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if module.isRunning {
                    Text("\(module.installed) modèles installés")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if !module.isRunning {
                Text("Lancez Ollama (app ou « ollama serve ») pour suivre vos modèles locaux.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if module.loaded.isEmpty {
                Text("Aucun modèle en mémoire.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(module.loaded) { model in
                    HStack(spacing: 8) {
                        Image(systemName: "cube.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text("\(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .memory)) · \(model.sizeVRAM > 0 ? String(localized: "GPU") : String(localized: "CPU"))")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if let expires = model.expiresAt, expires > Date() {
                            Text(expires, style: .relative)
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }
}
