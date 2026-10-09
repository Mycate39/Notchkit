import Darwin
import Foundation
import IOKit

/// Instantané des mesures du système (affiché par le moniteur système et le Dashboard).
struct SystemSnapshot: Equatable, Sendable {
    struct Process: Identifiable, Equatable, Sendable {
        let id: Int32
        let name: String
        /// Part d'un cœur (1 = un cœur à 100 %).
        let cpu: Double
        let memory: UInt64
    }

    var cpuTotal: Double = 0
    var cpuCores: [Double] = []
    var gpu: Double?
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    /// Débits réseau en octets par seconde.
    var networkIn: Double = 0
    var networkOut: Double = 0
    var batteryCycles: Int?
    /// Capacité maximale actuelle / capacité d'origine (santé de la batterie).
    var batteryHealth: Double?
    var topProcesses: [Process] = []
}

/// Calculs purs sur les compteurs du système (testés sans le système).
enum SystemMath {
    /// Ticks d'un cœur : utilisateur, système, inactif, nice.
    struct CoreTicks: Equatable, Sendable {
        var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
        var busy: UInt64 { user + system + nice }
        var total: UInt64 { busy + idle }
    }

    /// Charge d'un cœur entre deux relevés (0…1).
    static func usage(from old: CoreTicks, to new: CoreTicks) -> Double {
        let total = Double(new.total &- old.total)
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(new.busy &- old.busy) / total))
    }

    /// Débit (par seconde) d'un compteur croissant ; 0 si le compteur a été remis à zéro.
    static func rate(from old: UInt64, to new: UInt64, interval: TimeInterval) -> Double {
        guard interval > 0, new >= old else { return 0 }
        return Double(new - old) / interval
    }

    /// « 12,4 Mo/s » à partir d'un débit en octets par seconde.
    static func formattedRate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false // « 0 o » plutôt que « Zéro ko »
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}

/// Lecture des compteurs du système (API publiques : mach, IOKit, libproc, getifaddrs).
enum SystemReaders {
    static func coreTicks() -> [SystemMath.CoreTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(count)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            func value(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            return SystemMath.CoreTicks(user: value(CPU_STATE_USER), system: value(CPU_STATE_SYSTEM),
                                        idle: value(CPU_STATE_IDLE), nice: value(CPU_STATE_NICE))
        }
    }

    static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static func disk() -> (free: Int64, total: Int64) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values?.volumeTotalCapacity ?? 0))
    }

    /// Octets reçus et envoyés depuis le démarrage, toutes interfaces sauf la boucle locale.
    static func networkBytes() -> (input: UInt64, output: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var input: UInt64 = 0, output: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            input += UInt64(data.pointee.ifi_ibytes)
            output += UInt64(data.pointee.ifi_obytes)
        }
        return (input, output)
    }

    /// Utilisation du GPU (0…1) annoncée par le pilote (« Device Utilization % »), si disponible.
    static func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber
            else { continue }
            best = max(best ?? 0, value.doubleValue / 100)
        }
        return best
    }

    /// Cycles et santé de la batterie (MacBook), via le registre IOKit.
    static func battery() -> (cycles: Int?, health: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        }
        let cycles = number("CycleCount")
        let design = number("DesignCapacity")
        let maximum = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity") ?? number("MaxCapacity")
        let health = design.flatMap { design in maximum.map { design > 0 ? min(1, Double($0) / Double(design)) : 0 } }
        return (cycles, health)
    }

    /// Temps CPU cumulé (secondes) et mémoire de chaque processus.
    static func processes() -> [Int32: (name: String, cpuTime: Double, memory: UInt64)] {
        var pids = [Int32](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard bytes > 0 else { return [:] }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let toSeconds = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        var result: [Int32: (String, Double, UInt64)] = [:]
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            var usage = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard ok == 0 else { continue }
            var name = [CChar](repeating: 0, count: 256)
            proc_name(pid, &name, UInt32(name.count))
            let cpu = Double(usage.ri_user_time + usage.ri_system_time) * toSeconds
            result[pid] = (String(cString: name), cpu, usage.ri_phys_footprint)
        }
        return result
    }
}
