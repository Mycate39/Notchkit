import Foundation
import Network

/// Requête HTTP minimale (suffisante pour les hooks HTTP de Claude Code).
struct HTTPRequest: Sendable {
    let method: String
    let path: String
    /// En-têtes, noms en minuscules.
    let headers: [String: String]
    let body: Data
}

enum HTTPParser {
    enum Result: Sendable {
        case incomplete
        case invalid
        case tooLarge
        case complete(HTTPRequest)
    }

    static let maxBodySize = 16 * 1024 * 1024

    static func parse(_ data: Data) -> Result {
        // Les en-têtes tiennent dans les premiers 64 Ko : inutile de parcourir tout le corps.
        let searchEnd = data.index(data.startIndex, offsetBy: min(data.count, 64 * 1024))
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8), in: data.startIndex..<searchEnd) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0 else { return .invalid }
        guard length <= maxBodySize else { return .tooLarge }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }

        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(body)
        ))
    }

    static func response(status: Int, json: [String: Any]? = nil) -> Data {
        let reason = switch status {
        case 200: "OK"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        default: "Bad Request"
        }
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// Petit serveur HTTP local qui reçoit les hooks de Claude Code.
///
/// - n'écoute que sur 127.0.0.1 (inaccessible depuis le réseau) ;
/// - n'accepte que les requêtes portant le jeton secret écrit dans la configuration des hooks ;
/// - répond immédiatement ; si Notchkit n'est pas lancé, Claude Code ignore simplement l'échec.
@MainActor
final class ClaudeHookServer {
    enum State: Equatable {
        case stopped
        case listening(port: UInt16)
        case failed(String)
    }

    nonisolated static let path = "/notchkit/claude/hook"
    nonisolated static let tokenHeader = "x-notchkit-token"

    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }
    var onStateChange: (@MainActor (State) -> Void)?
    /// Traite un événement et renvoie la réponse JSON éventuelle pour Claude Code.
    var handler: (@MainActor ([String: Any]) -> [String: Any]?)?

    private let token: String
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(token: String) {
        self.token = token
    }

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            state = .failed(String(localized: "Port invalide"))
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] newState in
                MainActor.assumeIsolated {
                    switch newState {
                    case .ready: self?.state = .listening(port: port)
                    case let .failed(error): self?.state = .failed(error.localizedDescription)
                    case .cancelled: self?.state = .stopped
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        state = .stopped
    }

    // MARK: - Connexions

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .failed, .cancelled:
                MainActor.assumeIsolated { _ = self?.connections.removeValue(forKey: id) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }

                switch HTTPParser.parse(buffer) {
                case .incomplete:
                    if isComplete || error != nil {
                        connection.cancel()
                    } else {
                        self.receive(on: connection, buffer: buffer)
                    }
                case .invalid:
                    self.reply(on: connection, HTTPParser.response(status: 400))
                case .tooLarge:
                    self.reply(on: connection, HTTPParser.response(status: 413))
                case let .complete(request):
                    self.reply(on: connection, self.respond(to: request))
                }
            }
        }
    }

    private func respond(to request: HTTPRequest) -> Data {
        guard request.method == "POST", request.path == Self.path else {
            return HTTPParser.response(status: 404)
        }
        guard request.headers[Self.tokenHeader] == token else {
            return HTTPParser.response(status: 401)
        }
        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return HTTPParser.response(status: 400)
        }
        return HTTPParser.response(status: 200, json: handler?(json))
    }

    private func reply(on connection: NWConnection, _ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
