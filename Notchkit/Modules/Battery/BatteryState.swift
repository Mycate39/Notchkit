import Foundation
import IOKit.ps

/// Photographie de l'état de la batterie interne.
/// Construite à partir de la description fournie par IOKit (API publique « Power Sources »).
struct BatteryState: Equatable, Sendable {
    enum PowerSource: Sendable {
        case battery
        case ac
        case unknown
    }

    enum Status: Sendable {
        /// Branché et en cours de charge.
        case charging
        /// Branché et batterie pleine.
        case charged
        /// Branché mais la charge est en pause (recharge optimisée, limite de charge…).
        case pluggedNotCharging
        /// Sur batterie.
        case discharging
    }

    /// Niveau en pourcentage (0 à 100).
    var level: Int
    var isCharging: Bool
    var isCharged: Bool
    var powerSource: PowerSource
    /// Autonomie restante en minutes ; `nil` si inconnue ou en cours de calcul.
    var minutesToEmpty: Int?
    /// Temps avant la charge complète en minutes ; `nil` si inconnu.
    var minutesToFull: Int?

    var isPluggedIn: Bool { powerSource == .ac }

    var fraction: Double { Double(level) / 100 }

    var status: Status {
        if isPluggedIn {
            if isCharging { return .charging }
            return (isCharged || level >= 100) ? .charged : .pluggedNotCharging
        }
        return .discharging
    }

    /// Batterie faible : sur batterie et à 20 % ou moins.
    var isLow: Bool { !isPluggedIn && level <= 20 }
}

// MARK: - Lecture depuis IOKit

extension BatteryState {
    /// Crée l'état à partir d'une description de source d'alimentation IOKit.
    /// Renvoie `nil` si ce n'est pas une batterie interne (onduleur, Mac de bureau…).
    init?(description: [String: Any]) {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return nil }

        level = Swift.min(100, Swift.max(0, Int((Double(current) / Double(max) * 100).rounded())))
        isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        isCharged = description[kIOPSIsChargedKey] as? Bool ?? false

        switch description[kIOPSPowerSourceStateKey] as? String {
        case kIOPSACPowerValue: powerSource = .ac
        case kIOPSBatteryPowerValue: powerSource = .battery
        default: powerSource = .unknown
        }

        // IOKit renvoie -1 pendant le calcul, et 0 quand la valeur n'a pas de sens.
        func minutes(_ key: String) -> Int? {
            guard let value = description[key] as? Int, value > 0 else { return nil }
            return value
        }
        minutesToEmpty = powerSource == .battery ? minutes(kIOPSTimeToEmptyKey) : nil
        minutesToFull = isCharging ? minutes(kIOPSTimeToFullChargeKey) : nil
    }

    /// État actuel de la batterie interne, ou `nil` si le Mac n'en a pas.
    static func current() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let state = BatteryState(description: description) {
                return state
            }
        }
        return nil
    }
}

// MARK: - Détection des événements

/// Événement qui mérite une alerte dans l'encoche.
enum BatteryEvent: Equatable, Sendable {
    case pluggedIn
    case unplugged
    case low(threshold: Int)
}

/// Compare deux états successifs et en déduit l'événement à signaler.
/// Chaque seuil de batterie faible n'est signalé qu'une fois par décharge.
struct BatteryEventDetector {
    /// Seuils de batterie faible, du plus haut au plus bas.
    static let lowThresholds = [20, 10]

    private var alertedThresholds: Set<Int> = []

    mutating func process(from old: BatteryState?, to new: BatteryState?) -> BatteryEvent? {
        guard let new else { return nil }

        if new.isPluggedIn {
            alertedThresholds.removeAll()
        }

        // Au premier relevé (lancement de l'app), on n'annonce pas de branchement.
        if let old, old.isPluggedIn != new.isPluggedIn {
            if new.isPluggedIn { return .pluggedIn }
            if new.powerSource == .battery { return .unplugged }
        }

        guard new.powerSource == .battery else { return nil }

        // Seuil le plus bas franchi et pas encore signalé (les seuils au-dessus sont considérés comme vus).
        let crossed = Self.lowThresholds.filter { new.level <= $0 }
        guard let lowest = crossed.min(), !alertedThresholds.contains(lowest) else { return nil }
        alertedThresholds.formUnion(crossed)
        return .low(threshold: lowest)
    }
}
