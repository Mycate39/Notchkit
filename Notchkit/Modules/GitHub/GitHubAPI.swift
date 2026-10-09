import Foundation
import Security

/// Jeton d'accès personnel GitHub, rangé dans le trousseau de macOS (jamais en clair sur le disque).
enum GitHubToken {
    private static let service = "com.andeolchenaux.notchkit.github"
    private static let account = "personal-access-token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Une pull request suivie dans l'encoche.
struct PullRequest: Identifiable, Equatable, Sendable {
    enum Checks: Equatable, Sendable { case none, pending, success, failure }

    let id: Int
    let number: Int
    let title: String
    let repository: String
    let url: URL
    var checks: Checks = .none
    var isDraft = false
}

/// Logique pure : synthèse des vérifications d'un commit.
enum PullRequestChecks {
    /// Un échec l'emporte, puis une vérification en cours ; sinon succès (ou aucune vérification).
    static func summary(statuses: [String], conclusions: [String?]) -> PullRequest.Checks {
        let failing = ["failure", "timed_out", "cancelled", "action_required", "error", "startup_failure"]
        if conclusions.contains(where: { $0.map(failing.contains) ?? false }) || statuses.contains(where: failing.contains) {
            return .failure
        }
        if conclusions.contains(where: { $0 == nil }) || statuses.contains("pending") { return .pending }
        return conclusions.isEmpty && statuses.isEmpty ? .none : .success
    }
}

/// Accès à l'API REST de GitHub (gratuite, avec le jeton de l'utilisateur).
struct GitHubClient: Sendable {
    let token: String
    var session: URLSession = .shared

    enum Failure: Error { case unauthorized, network }

    private func get(_ path: String) async throws -> Any {
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(code) else { throw Failure.network }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Pull requests ouvertes correspondant à une recherche (ex. `author:@me`).
    func search(_ qualifier: String) async throws -> [PullRequest] {
        let query = "is:pr is:open archived:false \(qualifier)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let json = try await get("/search/issues?q=\(query)&per_page=10&sort=updated")
        let items = (json as? [String: Any])?["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = item["id"] as? Int, let number = item["number"] as? Int,
                  let title = item["title"] as? String,
                  let link = (item["html_url"] as? String).flatMap(URL.init(string:)),
                  let repositoryURL = item["repository_url"] as? String
            else { return nil }
            let repository = repositoryURL.components(separatedBy: "/repos/").last ?? ""
            return PullRequest(id: id, number: number, title: title, repository: repository, url: link,
                               isDraft: item["draft"] as? Bool ?? false)
        }
    }

    /// État des vérifications (check runs + statuts) du dernier commit d'une pull request.
    func checks(for pull: PullRequest) async throws -> PullRequest.Checks {
        let detail = try await get("/repos/\(pull.repository)/pulls/\(pull.number)") as? [String: Any]
        guard let sha = (detail?["head"] as? [String: Any])?["sha"] as? String else { return .none }
        let runs = (try await get("/repos/\(pull.repository)/commits/\(sha)/check-runs?per_page=50") as? [String: Any])?["check_runs"]
            as? [[String: Any]] ?? []
        let combined = try await get("/repos/\(pull.repository)/commits/\(sha)/status") as? [String: Any]
        let statuses = (combined?["statuses"] as? [[String: Any]] ?? []).compactMap { $0["state"] as? String }
        return PullRequestChecks.summary(statuses: statuses, conclusions: runs.map { $0["conclusion"] as? String })
    }
}
