import Foundation
import ServiceManagement

/// Côté app de l'assistant système : installation (`SMAppService.daemon`, accord de l'utilisateur dans
/// Réglages Système > Général > Ouverture) et commandes envoyées par XPC.
@MainActor
final class AwakeHelperClient {
    enum State: Equatable {
        /// Pas encore installé.
        case notInstalled
        /// Installé, en attente de l'accord de l'utilisateur dans Réglages Système.
        case needsApproval
        case ready
        case failed(String)
    }

    private var service: SMAppService { .daemon(plistName: AwakeHelper.plistName) }
    private var connection: NSXPCConnection?

    var state: State {
        switch service.status {
        case .enabled: .ready
        case .requiresApproval: .needsApproval
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .notInstalled
        }
    }

    /// Installe l'assistant. macOS demande ensuite l'accord dans Réglages Système.
    func install() -> State {
        do {
            try service.register()
        } catch {
            // Déjà installé mais pas encore approuvé : macOS renvoie une erreur, l'état suffit.
            if state == .notInstalled { return .failed(error.localizedDescription) }
        }
        return state
    }

    func uninstall() async {
        connection?.invalidate()
        connection = nil
        try? await service.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
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

    /// Envoie une commande ; `nil` si l'assistant ne répond pas (non installé, refusé, arrêté).
    private func call<T: Sendable>(_ body: @escaping (AwakeHelperProtocol, @escaping @Sendable (T) -> Void) -> Void) async -> T? {
        guard state == .ready else { return nil }
        let connection = currentConnection()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) } as? AwakeHelperProtocol
            guard let proxy else { return once.resume(nil) }
            body(proxy) { once.resume($0) }
        }
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: AwakeHelper.label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AwakeHelperProtocol.self)
        // L'assistant doit être le nôtre (même exigence de signature, à l'identifiant près).
        connection.setCodeSigningRequirement(AwakeHelper.clientRequirement.replacingOccurrences(
            of: "com.andeolchenaux.notchkit\"", with: "com.andeolchenaux.notchkit.awake\""))
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// Reprend une continuation une seule fois (réponse ou erreur de connexion, la première qui arrive).
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
