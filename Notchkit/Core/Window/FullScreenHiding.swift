import AppKit
import IOKit.pwr_mgt

/// Masque l'encoche pendant une vidéo en plein écran sur l'écran de l'encoche (réglage
/// `AppSettings.hidesInFullScreen`) : plus de forme noire par-dessus YouTube, Netflix, QuickTime…
/// Une vidéo se reconnaît à ce que son lecteur empêche la mise en veille de l'écran (API publique
/// d'IOKit) ; la musique, une page ou un document en plein écran gardent l'encoche. Vérifié au
/// changement d'app, de bureau, et chaque seconde (lecture lancée ou arrêtée sans autre signal).
@MainActor
final class FullScreenHiding {
    private static let checkInterval: TimeInterval = 1

    private let isEnabled: () -> Bool
    private let screen: () -> NSScreen?
    private let onChange: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private(set) var isHidden = false

    init(isEnabled: @escaping () -> Bool, screen: @escaping () -> NSScreen?, onChange: @escaping (Bool) -> Void) {
        self.isEnabled = isEnabled
        self.screen = screen
        self.onChange = onChange
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func check() {
        let hidden = isEnabled() && !AutomatedRun.isActive && frontAppIsFullScreen() && Self.isVideoPlaying()
        guard hidden != isHidden else { return }
        isHidden = hidden
        onChange(hidden)
    }

    /// Types d'assertion d'un lecteur qui garde l'écran allumé.
    nonisolated private static let displaySleepAssertions: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    /// Un autre processus empêche la mise en veille de l'écran (fonction pure, testée).
    nonisolated static func isVideoPlaying(assertionsByProcess: [Int: [[String: Any]]], excluding ownPID: Int) -> Bool {
        assertionsByProcess.contains { pid, assertions in
            pid != ownPID && assertions.contains { assertion in
                (assertion["AssertType"] as? String).map(displaySleepAssertions.contains) ?? false
            }
        }
    }

    private static func isVideoPlaying() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let raw = unmanaged?.takeRetainedValue() as NSDictionary? else { return false }
        var byProcess: [Int: [[String: Any]]] = [:]
        for case let (pid as NSNumber, assertions as [[String: Any]]) in raw {
            byProcess[pid.intValue] = assertions
        }
        return isVideoPlaying(assertionsByProcess: byProcess, excluding: Int(ProcessInfo.processInfo.processIdentifier))
    }

    private func frontAppIsFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let number = screen()?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        let display = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        return FullScreenDetector.isFullScreen(pid: app.processIdentifier, display: display)
    }
}
