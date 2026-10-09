import Foundation
import Observation

/// Échantillonneur partagé des mesures du système. Il ne tourne que tant qu'une vue l'utilise
/// (`acquire` / `release`) : au repos, aucun relevé, aucune consommation.
@MainActor
@Observable
final class SystemSampler {
    static let shared = SystemSampler()
    static let interval: TimeInterval = 2

    private(set) var snapshot = SystemSnapshot()

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var previous: Raw?

    /// Relevés bruts, comparés d'un tour à l'autre pour calculer charges et débits.
    private struct Raw: Sendable {
        let date: Date
        let cores: [SystemMath.CoreTicks]
        let network: (input: UInt64, output: UInt64)
        let processes: [Int32: (name: String, cpuTime: Double, memory: UInt64)]
    }

    func acquire() {
        users += 1
        guard loop == nil, !AutomatedRun.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        loop?.cancel()
        loop = nil
        previous = nil
    }

    private func sample() async {
        // Relevés hors du fil principal (la liste des processus prend quelques millisecondes).
        let (raw, extra) = await Task.detached(priority: .utility) {
            let raw = Raw(date: Date(), cores: SystemReaders.coreTicks(), network: SystemReaders.networkBytes(),
                          processes: SystemReaders.processes())
            let battery = SystemReaders.battery()
            let disk = SystemReaders.disk()
            return (raw, (memory: SystemReaders.memoryUsed(), gpu: SystemReaders.gpuUsage(),
                          disk: disk, cycles: battery.cycles, health: battery.health))
        }.value

        var next = snapshot
        next.memoryUsed = extra.memory
        next.gpu = extra.gpu
        next.diskFree = extra.disk.free
        next.diskTotal = extra.disk.total
        next.batteryCycles = extra.cycles
        next.batteryHealth = extra.health

        if let previous, previous.cores.count == raw.cores.count {
            let interval = raw.date.timeIntervalSince(previous.date)
            next.cpuCores = zip(previous.cores, raw.cores).map { SystemMath.usage(from: $0, to: $1) }
            next.cpuTotal = next.cpuCores.isEmpty ? 0 : next.cpuCores.reduce(0, +) / Double(next.cpuCores.count)
            next.networkIn = SystemMath.rate(from: previous.network.input, to: raw.network.input, interval: interval)
            next.networkOut = SystemMath.rate(from: previous.network.output, to: raw.network.output, interval: interval)
            next.topProcesses = raw.processes.compactMap { pid, value -> SystemSnapshot.Process? in
                guard let old = previous.processes[pid], interval > 0 else { return nil }
                let cpu = max(0, value.cpuTime - old.cpuTime) / interval
                return SystemSnapshot.Process(id: pid, name: value.name, cpu: cpu, memory: value.memory)
            }
            .sorted { $0.cpu > $1.cpu }
            .prefix(5)
            .map { $0 }
        }
        previous = raw
        if next != snapshot { snapshot = next }
    }
}

#if DEBUG
extension SystemSampler {
    /// Relevé réel immédiat (deux mesures à une demi-seconde d'écart), pour les images de démonstration.
    func debugSampleNow() {
        let cores = SystemReaders.coreTicks()
        let network = SystemReaders.networkBytes()
        let processes = SystemReaders.processes()
        Thread.sleep(forTimeInterval: 0.5)
        var next = SystemSnapshot()
        next.cpuCores = zip(cores, SystemReaders.coreTicks()).map { SystemMath.usage(from: $0, to: $1) }
        next.cpuTotal = next.cpuCores.isEmpty ? 0 : next.cpuCores.reduce(0, +) / Double(next.cpuCores.count)
        let networkNow = SystemReaders.networkBytes()
        next.networkIn = SystemMath.rate(from: network.input, to: networkNow.input, interval: 0.5)
        next.networkOut = SystemMath.rate(from: network.output, to: networkNow.output, interval: 0.5)
        next.memoryUsed = SystemReaders.memoryUsed()
        next.gpu = SystemReaders.gpuUsage()
        let disk = SystemReaders.disk()
        next.diskFree = disk.free
        next.diskTotal = disk.total
        let battery = SystemReaders.battery()
        next.batteryCycles = battery.cycles
        next.batteryHealth = battery.health
        next.topProcesses = SystemReaders.processes().compactMap { pid, value -> SystemSnapshot.Process? in
            guard let old = processes[pid] else { return nil }
            return SystemSnapshot.Process(id: pid, name: value.name, cpu: max(0, value.cpuTime - old.cpuTime) / 0.5,
                                          memory: value.memory)
        }.sorted { $0.cpu > $1.cpu }.prefix(5).map { $0 }
        snapshot = next
    }
}
#endif
