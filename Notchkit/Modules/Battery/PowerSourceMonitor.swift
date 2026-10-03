import Foundation
import IOKit.ps

/// Prévient quand l'alimentation change (branchement, niveau, état de charge).
///
/// Utilise `IOPSNotificationCreateRunLoopSource` (API publique) : c'est macOS qui nous
/// appelle à chaque changement, il n'y a aucun relevé périodique.
@MainActor
final class PowerSourceMonitor {
    private var runLoopSource: CFRunLoopSource?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard runLoopSource == nil else { return }

        // L'API attend une fonction C : on lui passe un pointeur vers `self` comme contexte.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // La source est ajoutée à la boucle principale : on est déjà sur le thread principal.
            MainActor.assumeIsolated { monitor.onChange() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        runLoopSource = nil
    }
}
