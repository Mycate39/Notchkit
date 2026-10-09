import SwiftUI
import Observation

/// Module Moniteur système : CPU par cœur, GPU, mémoire, disque, réseau, santé de la batterie
/// et processus les plus gourmands. Les relevés ne tournent que pendant que la carte est visible.
@MainActor
@Observable
final class SystemMonitorModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "sysmon",
        name: "Moniteur système",
        summary: "Processeur, graphismes, mémoire, disque, réseau, batterie et processus gourmands.",
        systemImage: "gauge.with.dots.needle.67percent",
        category: .system,
        tier: .free,
        defaultEnabled: false
    )

    init(context: ModuleContext) {}

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView { AnyView(SystemMonitorMiniView()) }
    func expandedView() -> AnyView { AnyView(SystemMonitorExpandedView()) }
}

/// Démarre l'échantillonneur tant que la vue est affichée.
private struct SamplerLifetime: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { SystemSampler.shared.acquire() }
            .onDisappear { SystemSampler.shared.release() }
    }
}

extension View {
    /// Les mesures du système sont relevées tant que cette vue est visible.
    func samplesSystem() -> some View { modifier(SamplerLifetime()) }
}

enum SystemFormat {
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

struct SystemMonitorExpandedView: View {
    @Environment(\.widgetSize) private var size
    private var sampler: SystemSampler { .shared }

    var body: some View {
        let s = sampler.snapshot
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(SystemFormat.percent(s.cpuTotal))
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tint)
                    Text("Processeur")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                CoreBars(values: s.cpuCores)
                    .frame(height: 18)
                metric("Mémoire", value: "\(SystemFormat.bytes(s.memoryUsed)) / \(SystemFormat.bytes(s.memoryTotal))",
                       fraction: s.memoryTotal > 0 ? Double(s.memoryUsed) / Double(s.memoryTotal) : 0)
                metric("Disque", value: String(localized: "\(ByteCountFormatter.string(fromByteCount: s.diskFree, countStyle: .file)) libres"),
                       fraction: s.diskTotal > 0 ? 1 - Double(s.diskFree) / Double(s.diskTotal) : 0)
            }
            if size == .large {
                VStack(alignment: .leading, spacing: 5) {
                    detail("cpu", s.gpu.map { String(localized: "GPU \(SystemFormat.percent($0))") } ?? String(localized: "GPU —"))
                    detail("arrow.down", SystemMath.formattedRate(s.networkIn))
                    detail("arrow.up", SystemMath.formattedRate(s.networkOut))
                    if let health = s.batteryHealth {
                        HStack(spacing: 10) {
                            detail("battery.100", SystemFormat.percent(health))
                                .help("Santé de la batterie")
                            if let cycles = s.batteryCycles {
                                detail("arrow.triangle.2.circlepath", "\(cycles)")
                                    .help("Cycles de charge")
                            }
                        }
                    }
                    Divider().overlay(.white.opacity(0.15))
                    ForEach(s.topProcesses.prefix(3)) { process in
                        HStack(spacing: 4) {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(SystemFormat.percent(process.cpu))
                                .monospacedDigit()
                                .foregroundStyle(process.cpu > 0.5 ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.6)))
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .samplesSystem()
    }

    private func metric(_ title: LocalizedStringKey, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer(minLength: 4)
                Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            StandByBar(value: fraction, height: 5)
        }
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
    }
}

/// Une barre verticale par cœur.
private struct CoreBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(StandBy.surface)
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(.tint)
                                .frame(height: max(2, proxy.size.height * value))
                        }
                        .frame(maxWidth: 8)
                }
            }
            .animation(.snappy, value: values)
        }
    }
}

struct SystemMonitorMiniView: View {
    private var sampler: SystemSampler { .shared }

    var body: some View {
        MiniWidget(symbol: "cpu", value: SystemFormat.percent(sampler.snapshot.cpuTotal),
                   caption: String(localized: "Processeur"))
            .samplesSystem()
    }
}
