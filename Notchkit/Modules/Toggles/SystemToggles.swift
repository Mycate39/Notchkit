import AppKit
import IOKit.pwr_mgt

/// Mode sombre de macOS, via les préférences d'apparence de System Events (AppleScript, API publique ;
/// macOS demande une fois l'autorisation de piloter System Events).
enum DarkMode {
    static var isOn: Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
    }

    /// Renvoie faux si le changement a été refusé (autorisation non accordée).
    @MainActor
    @discardableResult
    static func set(_ dark: Bool) -> Bool {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}

/// Empêche le Mac (et l'écran) de se mettre en veille, comme `caffeinate` (API publique IOKit).
@MainActor
final class SleepPreventer {
    private var assertion: IOPMAssertionID = 0

    var isActive: Bool { assertion != 0 }

    func setActive(_ active: Bool) {
        if active, assertion == 0 {
            var id: IOPMAssertionID = 0
            let reason = "Notchkit : mode anti-veille" as CFString
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                assertion = id
            }
        } else if !active, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}

/// Icônes du bureau : réglage du Finder `CreateDesktop`, appliqué en relançant le Finder.
enum DesktopIcons {
    static var areVisible: Bool {
        UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool ?? true
    }

    static func setVisible(_ visible: Bool) {
        run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", visible ? "true" : "false"])
        run("/usr/bin/killall", ["Finder"])
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}

/// Verrouille le clavier pour le nettoyer : les touches sont avalées (event tap, autorisation
/// Accessibilité) jusqu'au déverrouillage depuis l'encoche ou la fin du délai.
@MainActor
final class KeyboardCleaningLock {
    /// Port du tap, accessible depuis le rappel C (pour le réactiver si macOS le coupe).
    private final class TapBox { var port: CFMachPort? }

    private(set) var isLocked = false
    private let box = TapBox()
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Renvoie faux sans l'autorisation Accessibilité.
    func lock() -> Bool {
        guard !isLocked, Self.isTrusted else { return isLocked }
        // Touches, modificateurs et touches spéciales (14 = NX_SYSDEFINED : volume, luminosité…).
        let types: [UInt32] = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue, 14]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon, let port = Unmanaged<TapBox>.fromOpaque(refcon).takeUnretainedValue().port {
                    CGEvent.tapEnable(tap: port, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            return nil // touche avalée
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(box).toOpaque())
        else { return false }
        box.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.source = source
        isLocked = true
        return true
    }

    func unlock() {
        guard isLocked else { return }
        if let port = box.port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        box.port = nil
        source = nil
        isLocked = false
    }
}
