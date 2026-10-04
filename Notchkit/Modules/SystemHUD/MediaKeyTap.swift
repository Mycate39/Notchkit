import AppKit
import ApplicationServices

/// Touches spéciales du clavier (volume, luminosité) reçues par l'interception.
enum MediaKey: Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown

    /// Codes NX_KEYTYPE_* (IOKit, ev_keymap.h).
    init?(keyCode: Int) {
        switch keyCode {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }

    /// Décode le champ `data1` d'un événement NX_SYSDEFINED (sous-type 8).
    /// Renvoie la touche et vrai si elle est enfoncée (faux au relâchement).
    static func decode(data1: Int) -> (key: MediaKey, isDown: Bool, isRepeat: Bool)? {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0x0000_FFFF
        let state = (flags & 0xFF00) >> 8
        guard let key = MediaKey(keyCode: keyCode) else { return nil }
        return (key, state == 0x0A, flags & 0x1 == 1)
    }
}

/// Intercepte les touches volume/luminosité pour remplacer l'indicateur de macOS.
///
/// Utilise un « event tap » (API publique), qui demande l'autorisation Accessibilité.
/// Le gestionnaire renvoie vrai s'il a traité la touche : elle est alors retirée et macOS
/// n'affiche pas son propre indicateur. Sinon, la touche suit son chemin normal.
@MainActor
final class MediaKeyTap {
    /// Touche reçue (enfoncée), avec les modificateurs. Renvoie vrai si elle a été traitée.
    var handler: (@MainActor (MediaKey, NSEvent.ModifierFlags) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Demande l'autorisation Accessibilité (fenêtre de macOS).
    static func requestTrust() {
        // Clé « AXTrustedCheckOptionPrompt » (valeur de kAXTrustedCheckOptionPrompt).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var isRunning: Bool { tap != nil }

    /// Démarre l'interception (échoue sans l'autorisation Accessibilité).
    @discardableResult
    func start() -> Bool {
        guard tap == nil, Self.isTrusted else { return tap != nil }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                // On n'extrait que des valeurs simples de l'événement avant de passer au thread
                // principal (où le tap est installé) : l'événement lui-même reste ici.
                let rawType = type.rawValue
                var subtype: Int16 = -1
                var data1 = 0
                var flags: UInt = 0
                if rawType == 14, let nsEvent = NSEvent(cgEvent: event) {
                    subtype = nsEvent.subtype.rawValue
                    data1 = nsEvent.data1
                    flags = nsEvent.modifierFlags.rawValue
                }
                let swallow = MainActor.assumeIsolated {
                    owner.shouldSwallow(rawType: rawType, subtype: subtype, data1: data1, flags: flags)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Vrai si l'événement doit être retiré (touche traitée par Notchkit).
    private func shouldSwallow(rawType: UInt32, subtype: Int16, data1: Int, flags: UInt) -> Bool {
        // macOS désactive le tap s'il met trop de temps à répondre : on le réactive.
        if rawType == CGEventType.tapDisabledByTimeout.rawValue || rawType == CGEventType.tapDisabledByUserInput.rawValue {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard rawType == 14, subtype == 8, let decoded = MediaKey.decode(data1: data1) else { return false }

        // On traite l'appui ; le relâchement d'une touche traitée est aussi retiré.
        if decoded.isDown {
            let handled = handler?(decoded.key, NSEvent.ModifierFlags(rawValue: flags)) ?? false
            lastHandledKey = handled ? decoded.key : nil
            return handled
        }
        return lastHandledKey == decoded.key
    }

    private var lastHandledKey: MediaKey?
}
