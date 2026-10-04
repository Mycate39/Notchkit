import Foundation

/// Activité en cours affichée dans l'encoche : minuteur, téléchargement ou tâche externe.
struct LiveActivity: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case timer
        case download
        case task
    }

    let id: String
    let kind: Kind
    var title: String
    var symbol: String

    // Minuteur
    /// Fin prévue (minuteur en cours).
    var endDate: Date?
    /// Temps restant figé (minuteur en pause).
    var pausedRemaining: TimeInterval?
    var duration: TimeInterval = 0

    // Téléchargement ou tâche
    /// Progression 0…1 ; `nil` = indéterminée.
    var progress: Double?
    var detail: String?
    var fileURL: URL?

    var isFinished = false
    var finishedAt: Date?

    /// Temps restant d'un minuteur.
    func remaining(at date: Date = Date()) -> TimeInterval? {
        guard kind == .timer else { return nil }
        if isFinished { return 0 }
        if let pausedRemaining { return pausedRemaining }
        return endDate.map { max(0, $0.timeIntervalSince(date)) }
    }

    var isPaused: Bool { kind == .timer && pausedRemaining != nil && !isFinished }

    /// Avancement 0…1 (minuteur : temps écoulé ; sinon : progression connue).
    func fraction(at date: Date = Date()) -> Double? {
        if isFinished { return 1 }
        switch kind {
        case .timer:
            guard duration > 0, let remaining = remaining(at: date) else { return nil }
            return min(1, max(0, 1 - remaining / duration))
        case .download, .task:
            return progress.map { min(1, max(0, $0)) }
        }
    }

    static func timer(duration: TimeInterval, title: String? = nil, now: Date = Date()) -> LiveActivity {
        LiveActivity(
            id: "timer-\(UUID().uuidString)",
            kind: .timer,
            title: title ?? String(localized: "Minuteur"),
            symbol: "timer",
            endDate: now.addingTimeInterval(duration),
            duration: duration
        )
    }
}

/// Ordre de priorité pour l'encoche repliée : minuteur qui vient de sonner, minuteurs en cours
/// (le plus proche d'abord), téléchargements, puis tâches.
enum LiveActivityRanking {
    static func mostRelevant(_ activities: [LiveActivity], at date: Date = Date()) -> LiveActivity? {
        if let ringing = activities.first(where: { $0.kind == .timer && $0.isFinished }) { return ringing }
        let running = activities.filter { !$0.isFinished }
        if let timer = running.filter({ $0.kind == .timer && !$0.isPaused })
            .min(by: { ($0.remaining(at: date) ?? 0) < ($1.remaining(at: date) ?? 0) }) {
            return timer
        }
        return running.first { $0.kind == .download } ?? running.first { $0.kind == .task }
            ?? running.first
    }
}

// MARK: - Commandes externes (liens notchkit://)

/// Commandes reçues par lien `notchkit://`, pour que scripts et apps affichent leur progression :
/// - `notchkit://activity/update?id=build&title=Compilation&progress=0.4&symbol=hammer&detail=Étape%202`
/// - `notchkit://activity/end?id=build`
/// - `notchkit://timer/start?minutes=5&title=Thé`
enum LiveActivityCommand: Equatable, Sendable {
    case update(id: String, title: String?, progress: Double?, symbol: String?, detail: String?)
    case end(id: String)
    case startTimer(seconds: TimeInterval, title: String?)

    init?(url: URL) {
        guard url.scheme == "notchkit",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { _, last in last }
        )
        let action = (url.host() ?? "") + url.path

        switch action {
        case "activity/update":
            guard let id = query["id"], !id.isEmpty else { return nil }
            // Progression acceptée en 0…1 ou en pourcentage (0…100).
            let progress = query["progress"].flatMap(Double.init).map { $0 > 1 ? $0 / 100 : $0 }
            self = .update(id: id, title: query["title"], progress: progress, symbol: query["symbol"], detail: query["detail"])
        case "activity/end":
            guard let id = query["id"], !id.isEmpty else { return nil }
            self = .end(id: id)
        case "timer/start":
            let seconds = query["seconds"].flatMap(Double.init)
                ?? query["minutes"].flatMap(Double.init).map { $0 * 60 }
            guard let seconds, seconds > 0, seconds <= 24 * 3600 else { return nil }
            self = .startTimer(seconds: seconds, title: query["title"])
        default:
            return nil
        }
    }
}

// MARK: - Fichiers de téléchargement en cours

enum DownloadFiles {
    /// Extensions des fichiers temporaires des navigateurs.
    static let temporaryExtensions = ["crdownload", "download", "part", "partial", "opdownload"]

    static func isTemporary(_ name: String) -> Bool {
        temporaryExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Nom final du fichier (sans l'extension temporaire).
    static func finalName(for temporaryName: String) -> String {
        (temporaryName as NSString).deletingPathExtension
    }

    /// Taille lisible, ex. « 12,4 Mo ».
    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
