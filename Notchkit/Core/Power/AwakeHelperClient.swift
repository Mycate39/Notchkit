import AppKit
import OSLog
import ServiceManagement

/// Côté app de l'assistant système : installation et commandes envoyées par XPC.
///
/// L'assistant est installé à la manière classique, avec le mot de passe administrateur : copié dans
/// `/Library/PrivilegedHelperTools` et déclaré à launchd dans `/Library/LaunchDaemons`. `SMAppService` n'est pas
/// utilisable sans certificat Apple : macOS refuse de lancer un démon signé par « Notchkit Self-Signed » (chaîne
/// inconnue), et refuse d'enregistrer un démon ad hoc dans une app signée par ce certificat.
@MainActor
final class AwakeHelperClient {
    enum State: Equatable {
        /// Pas encore installé.
        case notInstalled
        /// Installé, mais d'une autre version que celle de l'app (mise à jour de Notchkit) : à réinstaller.
        case outdated
        case ready
        case failed(String)
    }

    private let log = Logger(subsystem: "com.andeolchenaux.notchkit", category: "capot")

    /// Délai maximal d'une réponse de l'assistant.
    nonisolated static let timeout: TimeInterval = 3

    nonisolated static let installedHelper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(AwakeHelper.label)")
    nonisolated static let installedPlist = URL(fileURLWithPath: "/Library/LaunchDaemons/\(AwakeHelper.plistName)")

    /// Assistant livré dans l'app (Contents/MacOS).
    static var bundledHelper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/NotchkitAwakeHelper")
    }

    private var connection: NSXPCConnection?
    private(set) var lastError: String?

    var state: State {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.installedHelper.path),
              fileManager.fileExists(atPath: Self.installedPlist.path)
        else { return .notInstalled }
        return fileManager.contentsEqual(atPath: Self.installedHelper.path, andPath: Self.bundledHelper.path) ? .ready : .outdated
    }

    // MARK: Installation

    /// Installe (ou met à jour) l'assistant. macOS demande le mot de passe administrateur.
    @discardableResult
    func install() -> State {
        lastError = nil
        removeLegacyRegistration()
        let plist = FileManager.default.temporaryDirectory.appendingPathComponent(AwakeHelper.plistName)
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: Self.launchdPlist, format: .xml, options: 0)
            try data.write(to: plist, options: .atomic)
        } catch {
            return .failed(error.localizedDescription)
        }
        connection?.invalidate()
        connection = nil
        let script = Self.installScript(bundledHelper: Self.bundledHelper.path, plist: plist.path)
        if let error = Self.runAsAdministrator(script) {
            lastError = error
            log.error("Installation de l'assistant impossible : \(error, privacy: .public)")
            return .failed(error)
        }
        return state
    }

    /// Retire l'assistant (mot de passe administrateur). La veille normale revient.
    func uninstall() {
        connection?.invalidate()
        connection = nil
        if let error = Self.runAsAdministrator(Self.uninstallScript) {
            lastError = error
        }
    }

    /// Déclaration launchd : lancé à la demande par son service XPC, en administrateur.
    nonisolated static var launchdPlist: [String: Any] {
        [
            "Label": AwakeHelper.label,
            "ProgramArguments": [installedHelper.path],
            "MachServices": [AwakeHelper.label: true],
        ]
    }

    /// Script shell exécuté en administrateur (chemins entre apostrophes). Fonction pure, testée.
    nonisolated static func installScript(bundledHelper: String, plist: String) -> String {
        let label = AwakeHelper.label
        return [
            "/bin/launchctl bootout system/\(label) 2>/dev/null",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp -f \(quoted(bundledHelper)) \(quoted(installedHelper.path))",
            "/usr/sbin/chown root:wheel \(quoted(installedHelper.path))",
            "/bin/chmod 755 \(quoted(installedHelper.path))",
            "/bin/cp -f \(quoted(plist)) \(quoted(installedPlist.path))",
            "/usr/sbin/chown root:wheel \(quoted(installedPlist.path))",
            "/bin/chmod 644 \(quoted(installedPlist.path))",
            "/bin/launchctl bootstrap system \(quoted(installedPlist.path))",
        ].joined(separator: " ; ")
    }

    nonisolated static var uninstallScript: String {
        [
            "/bin/launchctl bootout system/\(AwakeHelper.label) 2>/dev/null",
            "/bin/rm -f \(quoted(installedPlist.path)) \(quoted(installedHelper.path))",
            "/usr/bin/pmset -a disablesleep 0",
        ].joined(separator: " ; ")
    }

    nonisolated static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Lance un script avec les droits administrateur (macOS demande le mot de passe). Renvoie l'erreur éventuelle.
    private static func runAsAdministrator(_ script: String) -> String? {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let prompt = String(localized: "Notchkit installe son assistant pour garder le Mac éveillé capot fermé.")
            .replacingOccurrences(of: "\"", with: "'")
        let source = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        var error: NSDictionary?
        NSApp.activate()
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        // -128 : l'utilisateur a annulé.
        if error[NSAppleScript.errorNumber] as? Int == -128 { return String(localized: "Installation annulée.") }
        return error[NSAppleScript.errorMessage] as? String ?? String(localized: "Erreur inconnue")
    }

    /// Premiers essais : l'assistant passait par `SMAppService`, qui ne marche pas avec notre certificat.
    /// On retire cet enregistrement s'il existe encore.
    private func removeLegacyRegistration() {
        let service = SMAppService.daemon(plistName: AwakeHelper.plistName)
        guard service.status != .notRegistered, service.status != .notFound else { return }
        service.unregister { _ in }
    }

    // MARK: Commandes

    func setSleepDisabled(_ disabled: Bool) async -> Bool {
        await call { proxy, done in proxy.setSleepDisabled(disabled) { done($0) } } ?? false
    }

    func sleepNow() async -> Bool {
        await call { proxy, done in proxy.sleepNow { done($0) } } ?? false
    }

    func helperVersion() async -> String? {
        await call { proxy, done in proxy.version { done($0) } }
    }

    /// Envoie une commande ; `nil` si l'assistant ne répond pas (non installé, arrêté).
    private func call<T: Sendable>(_ body: @escaping @Sendable (AwakeHelperProtocol, @escaping @Sendable (T) -> Void) -> Void) async -> T? {
        guard state == .ready else { return nil }
        let result = await Self.send(over: XPCBox(currentConnection()), body)
        if result == nil { log.error("L'assistant ne répond pas") }
        return result
    }

    /// Hors du fil principal : réponses et erreurs arrivent sur une file de XPC, pas sur le fil principal
    /// (une fermeture héritée du fil principal y ferait planter l'app au contrôle d'isolation de Swift).
    private nonisolated static func send<T: Sendable>(
        over box: XPCBox<NSXPCConnection>,
        _ body: @escaping @Sendable (AwakeHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(continuation)
            // Sans réponse (assistant bloqué ou absent), on n'attend pas indéfiniment.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
            let proxy = box.value.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) } as? AwakeHelperProtocol
            guard let proxy else { return once.resume(nil) }
            body(proxy) { once.resume($0) }
        }
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: AwakeHelper.label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AwakeHelperProtocol.self)
        // L'assistant doit être le nôtre (signé ad hoc : on vérifie son identifiant ; il ne s'installe qu'avec
        // le mot de passe administrateur, dans un dossier réservé à root).
        connection.setCodeSigningRequirement("identifier \"\(AwakeHelper.label)\"")
        // Appelés sur une file de XPC : fermetures `@Sendable`, jamais isolées au fil principal.
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// Objet système (connexion XPC) passé hors du fil principal : il est sûr d'emploi depuis n'importe quel fil.
private struct XPCBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Reprend une continuation une seule fois (réponse, erreur de connexion ou délai, la première qui arrive).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
