import Foundation

/// Assistant système de Notchkit, lancé en administrateur par launchd (`SMAppService.daemon`).
///
/// Il ne sait faire que trois choses : couper la veille (capot fermé compris), la rétablir, et endormir le Mac.
/// Sécurités : il n'accepte que Notchkit (exigence de signature), rétablit la veille à son lancement et dès que
/// Notchkit se déconnecte (app quittée ou plantée), puis s'arrête ; launchd le relance à la demande.
final class AwakeHelperService: NSObject, NSXPCListenerDelegate, AwakeHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "notchkit.awake.helper")
    private var clients = 0
    private var exitWork: DispatchWorkItem?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(AwakeHelper.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: AwakeHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in self?.clientLeft() }
        queue.sync {
            clients += 1
            exitWork?.cancel()
            exitWork = nil
        }
        connection.resume()
        return true
    }

    /// Notchkit s'est déconnectée : la veille revient, puis l'assistant s'arrête s'il n'a plus de client.
    private func clientLeft() {
        queue.async { [self] in
            clients = max(0, clients - 1)
            guard clients == 0 else { return }
            _ = Self.pmset(["-a", "disablesleep", "0"])
            let work = DispatchWorkItem { [self] in
                if clients == 0 { exit(0) }
            }
            exitWork = work
            queue.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
        reply(Self.pmset(["-a", "disablesleep", disabled ? "1" : "0"]))
    }

    func sleepNow(reply: @escaping (Bool) -> Void) {
        reply(Self.pmset(["sleepnow"]))
    }

    func version(reply: @escaping (String) -> Void) {
        reply(AwakeHelper.version)
    }

    static func pmset(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// Au lancement, la veille revient toujours : un état « veille coupée » ne survit jamais à un plantage.
_ = AwakeHelperService.pmset(["-a", "disablesleep", "0"])
let service = AwakeHelperService()
let listener = NSXPCListener(machServiceName: AwakeHelper.label)
listener.delegate = service
listener.resume()
dispatchMain()
