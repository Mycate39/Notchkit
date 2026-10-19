import Foundation
import Observation

/// Déploiement Vercel (lecture seule).
struct VercelDeployment: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case ready, building, error, canceled, queued }

    let id: String
    let project: String
    let state: State
    let created: Date
    let message: String?
}

/// Paiement Stripe (lecture seule).
struct StripeCharge: Identifiable, Equatable, Sendable {
    let id: String
    /// Montant en unité principale (euros…).
    let amount: Double
    let currency: String
    let customer: String?
    let created: Date
}

/// Lecture des réponses des API (fonctions pures, testées).
enum ServiceParsing {
    static func vercelDeployments(from data: Data) -> [VercelDeployment] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["deployments"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["uid"] as? String, let name = item["name"] as? String else { return nil }
            let raw = (item["state"] ?? item["readyState"]) as? String ?? ""
            let state: VercelDeployment.State = switch raw.uppercased() {
            case "READY": .ready
            case "ERROR": .error
            case "CANCELED": .canceled
            case "QUEUED", "INITIALIZING": .queued
            default: .building
            }
            let created = (item["created"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
            let message = (item["meta"] as? [String: Any])?["githubCommitMessage"] as? String
            return VercelDeployment(id: id, project: name, state: state, created: created,
                                    message: message.map { String($0.prefix(80)) })
        }
    }

    /// Paiements réussis (les montants Stripe sont en centimes, sauf devises sans décimales).
    static func stripeCharges(from data: Data) -> [StripeCharge] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let cents = item["amount"] as? Double,
                  item["status"] as? String == "succeeded", item["refunded"] as? Bool != true else { return nil }
            let currency = (item["currency"] as? String ?? "eur").uppercased()
            let name = (item["billing_details"] as? [String: Any])?["name"] as? String
            let created = (item["created"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? .distantPast
            return StripeCharge(id: id, amount: cents / divisor(for: currency), currency: currency,
                                customer: name, created: created)
        }
    }

    /// Déploiements qui étaient en cours et viennent de se terminer : leur nouvel état.
    static func finishedDeployments(old: [VercelDeployment], new: [VercelDeployment]) -> [VercelDeployment.State] {
        let pending = Set(old.filter { $0.state == .building || $0.state == .queued }.map(\.id))
        return new.filter { pending.contains($0.id) && ($0.state == .ready || $0.state == .error) }.map(\.state)
    }

    /// Devises sans centimes chez Stripe (yen, won…).
    static func divisor(for currency: String) -> Double {
        ["JPY", "KRW", "VND", "CLP", "ISK", "XOF", "XAF"].contains(currency) ? 1 : 100
    }

    /// Total encaissé (devise du premier paiement ; les autres devises sont ignorées).
    static func total(of charges: [StripeCharge]) -> (amount: Double, currency: String)? {
        guard let currency = charges.first?.currency else { return nil }
        return (charges.filter { $0.currency == currency }.reduce(0) { $0 + $1.amount }, currency)
    }
}

/// Services suivis par la page Agents : Vercel et Stripe (clés de l'utilisateur, lecture seule),
/// GitHub étant lu dans son propre module.
@MainActor
@Observable
final class AgentServices {
    enum Service: String, CaseIterable, Identifiable {
        case github, vercel, stripe
        var id: String { rawValue }

        var title: String {
            switch self {
            case .github: "GitHub"
            case .vercel: "Vercel"
            case .stripe: "Stripe"
            }
        }

        /// Compte du trousseau pour la clé (GitHub a la sienne, dans son module).
        var keychainAccount: String? {
            switch self {
            case .github: nil
            case .vercel: "service.vercel"
            case .stripe: "service.stripe"
            }
        }
    }

    static let refreshInterval: TimeInterval = 300

    private(set) var deployments: [VercelDeployment] = []
    private(set) var charges: [StripeCharge] = []
    private(set) var errors: [Service: String] = [:]
    private(set) var configured: Set<Service> = []
    /// Appelé quand un nouveau paiement arrive (la mascotte se réjouit).
    @ObservationIgnored var onNewCharge: (() -> Void)?
    /// Appelé quand un déploiement suivi se termine (en ligne ou en échec).
    @ObservationIgnored var onDeploymentFinished: ((VercelDeployment.State) -> Void)?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var knownCharges: Set<String>?

    init() {
        refreshConfiguration()
    }

    #if DEBUG
    /// Données imposées pour les captures de développement.
    func setPreview(deployments: [VercelDeployment], charges: [StripeCharge]) {
        self.deployments = deployments
        self.charges = charges
        configured = [.vercel, .stripe]
    }
    #endif

    func refreshConfiguration() {
        configured = Set(Service.allCases.filter { service in
            service.keychainAccount.flatMap(Keychain.read)?.isEmpty == false
        })
    }

    func saveKey(_ key: String, for service: Service) {
        guard let account = service.keychainAccount else { return }
        _ = Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
        refreshConfiguration()
        Task { await refresh() }
    }

    func deleteKey(for service: Service) {
        guard let account = service.keychainAccount else { return }
        Keychain.delete(account)
        if service == .vercel { deployments = [] }
        if service == .stripe { charges = []; knownCharges = nil }
        errors[service] = nil
        refreshConfiguration()
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        guard !AutomatedRun.isActive else { return }
        if let key = Service.vercel.keychainAccount.flatMap(Keychain.read), !key.isEmpty {
            await load(.vercel, url: "https://api.vercel.com/v6/deployments?limit=6", key: key) { data in
                let deployments = ServiceParsing.vercelDeployments(from: data)
                for state in ServiceParsing.finishedDeployments(old: self.deployments, new: deployments) {
                    self.onDeploymentFinished?(state)
                }
                self.deployments = deployments
            }
        }
        if let key = Service.stripe.keychainAccount.flatMap(Keychain.read), !key.isEmpty {
            let startOfDay = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
            await load(.stripe, url: "https://api.stripe.com/v1/charges?limit=50&created[gte]=\(startOfDay)", key: key) { data in
                let charges = ServiceParsing.stripeCharges(from: data)
                let ids = Set(charges.map(\.id))
                if let known = self.knownCharges, !ids.subtracting(known).isEmpty { self.onNewCharge?() }
                self.knownCharges = ids
                self.charges = charges
            }
        }
    }

    private func load(_ service: Service, url: String, key: String, apply: (Data) -> Void) async {
        guard let url = URL(string: url) else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                errors[service] = status == 401 || status == 403
                    ? String(localized: "Clé refusée : vérifiez-la dans les réglages.")
                    : String(localized: "Erreur \(status) du service.")
                return
            }
            errors[service] = nil
            apply(data)
        } catch {
            errors[service] = String(localized: "Service injoignable.")
        }
    }
}
