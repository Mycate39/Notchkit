import Foundation

/// Échanges entre Notchkit et son assistant système (`NotchkitAwakeHelper`), qui tourne en administrateur.
/// Fichier partagé par les deux cibles : l'app et l'assistant.
@objc protocol AwakeHelperProtocol {
    /// Coupe (ou rétablit) la veille du Mac, y compris capot fermé (`pmset -a disablesleep`).
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void)
    /// Met le Mac en veille tout de suite (`pmset sleepnow`).
    func sleepNow(reply: @escaping (Bool) -> Void)
    /// Version de l'assistant : une app plus récente le réinstalle si elle diffère.
    func version(reply: @escaping (String) -> Void)
}

enum AwakeHelper {
    static let label = "com.andeolchenaux.notchkit.awake"
    static let plistName = "\(label).plist"
    /// À incrémenter quand l'assistant change.
    static let version = "1"

    /// Seule Notchkit peut parler à l'assistant. Les versions publiées sont signées par « Notchkit Self-Signed »
    /// (empreinte SHA-1 du certificat) ; les builds de développement, signés ad hoc, seulement par leur identifiant.
    static var clientRequirement: String {
        #if DEBUG
        "identifier \"com.andeolchenaux.notchkit\""
        #else
        "identifier \"com.andeolchenaux.notchkit\" and certificate leaf = H\"952B7D898E042CB28050D4C7143CFEBBB0065209\""
        #endif
    }
}
