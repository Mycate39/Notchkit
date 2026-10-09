import AppKit
import ApplicationServices
import Darwin

/// Dossier du projet ouvert dans l'app au premier plan : document d'Xcode (accessibilité)
/// ou dossier courant de l'onglet actif du Terminal (AppleScript + libproc).
enum ProjectDetector {
    static let xcodeID = "com.apple.dt.Xcode"
    static let terminalID = "com.apple.Terminal"

    @MainActor
    static func folder(for app: NSRunningApplication) -> URL? {
        switch app.bundleIdentifier {
        case xcodeID: xcodeDocument(pid: app.processIdentifier)
        case terminalID: terminalDirectory()
        default: nil
        }
    }

    /// Fichier du document de la fenêtre principale d'Xcode (projet, espace de travail ou fichier ouvert).
    static func xcodeDocument(pid: pid_t) -> URL? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXDocumentAttribute as CFString, &document) == .success,
              let string = document as? String, let url = URL(string: string), url.isFileURL
        else { return nil }
        return url
    }

    /// Dossier courant du processus au premier plan de l'onglet actif du Terminal.
    @MainActor
    static func terminalDirectory() -> URL? {
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Terminal\" to tty of selected tab of front window")
        guard let tty = script?.executeAndReturnError(&error).stringValue, error == nil else { return nil }
        var info = stat()
        guard stat(tty, &info) == 0 else { return nil }
        // Le processus le plus récent rattaché à ce terminal (le shell, ou la commande en cours).
        guard let pid = latestProcess(onDevice: UInt32(bitPattern: info.st_rdev)) else { return nil }
        return currentDirectory(of: pid)
    }

    private static func latestProcess(onDevice device: UInt32) -> pid_t? {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return nil }
        var best: pid_t?
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.e_tdev == device else { continue }
            if pid > (best ?? 0) { best = pid }
        }
        return best
    }

    private static func currentDirectory(of pid: pid_t) -> URL? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
}
