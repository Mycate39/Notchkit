import Foundation
import IOKit

/// Raison de garder le Mac éveillé capot fermé.
enum LidAwakeReason: Hashable, Sendable {
    /// Interrupteur (réglages, barre des menus, `notchkit awake`).
    case manual
    /// Un agent de code travaille (ou vient de travailler, pendant le délai calme).
    case agents
    /// Une commande `notchkit run --awake` tourne.
    case command(String)
}

/// Pourquoi un maintien s'est arrêté de lui-même.
enum LidAwakeStop: Equatable, Sendable {
    case battery(Int)
    case heat
    case unplugged
    case timer
}

/// Réglages du mode capot fermé.
struct LidAwakeSettings: Equatable, Sendable {
    static let batteryFloors = [10, 20, 30, 40, 50]
    static let quietDelays = [1, 3, 5, 10]
    static let durations: [Int?] = [nil, 30, 60, 120, 240]

    /// En dessous de ce niveau, sur batterie, le maintien s'arrête et le Mac s'endort.
    var batteryFloor = 20
    /// S'arrêter dès que le Mac passe sur batterie.
    var stopsWhenUnplugged = false
    /// Rester éveillé tant qu'un agent travaille.
    var followsAgents = true
    /// Minutes d'inactivité des agents avant de relâcher.
    var agentQuietMinutes = 3
}

/// Décisions du mode capot fermé (fonctions pures, testées).
enum LidAwakePolicy {
    /// Sécurité qui interdit de maintenir le Mac éveillé, ou `nil`.
    /// La chaleur ne compte que capot fermé (c'est là que le Mac ventile mal, surtout dans un sac).
    static func safetyStop(battery: BatteryState?, thermal: ProcessInfo.ThermalState, lidClosed: Bool,
                           settings: LidAwakeSettings) -> LidAwakeStop? {
        if lidClosed, thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue { return .heat }
        guard let battery, battery.powerSource == .battery else { return nil }
        if battery.level <= settings.batteryFloor { return .battery(battery.level) }
        if settings.stopsWhenUnplugged { return .unplugged }
        return nil
    }

    /// Les agents demandent-ils de rester éveillé ? Oui pendant leur travail, puis pendant le délai calme.
    static func agentsHold(working: Bool, lastActivity: Date?, now: Date, settings: LidAwakeSettings) -> Bool {
        guard settings.followsAgents else { return false }
        if working { return true }
        guard let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) < TimeInterval(settings.agentQuietMinutes * 60)
    }

    /// Fin d'un maintien à durée choisie.
    static func timerExpired(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now >= until
    }

    /// Faut-il endormir le Mac en relâchant ? macOS ne refait pas la mise en veille du capot fermé :
    /// si le capot est fermé au moment où le maintien s'arrête, c'est à Notchkit d'endormir le Mac.
    static func sleepsOnRelease(lidClosed: Bool) -> Bool { lidClosed }
}

/// Capot du MacBook fermé ? (propriété « AppleClamshellState » d'IOPMrootDomain, lisible sans droits.)
enum LidState {
    static func isClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
