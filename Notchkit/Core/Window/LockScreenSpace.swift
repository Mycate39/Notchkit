import AppKit
import os

private let spaceLog = Logger(subsystem: "com.andeolchenaux.notchkit", category: "espace")

/// Place l'encoche dans un « espace » SkyLight de niveau supérieur, au-dessus de tous les bureaux.
///
/// ⚠️ API privée (SkyLight), acceptée pour cet usage. Aucune interface publique ne permet
/// d'afficher une fenêtre au-dessus de l'écran verrouillé, ni de la soustraire aux transitions
/// entre bureaux : dans un bureau ordinaire, macOS retire le panneau en passant à une app en plein
/// écran, puis le remet d'un coup et le redimensionne. Dans cet espace, le panneau reste affiché
/// et immobile partout (bureaux, plein écran, écran verrouillé). Les fonctions sont chargées
/// dynamiquement : si l'une manque (mise à jour de macOS), `init` échoue et l'encoche garde le
/// comportement standard des fenêtres sur tous les bureaux.
@MainActor
final class LockScreenSpace {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpace = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    /// Niveau de l'espace. Niveaux connus de SkyLight : 100 assistant de configuration,
    /// 200 agent de sécurité, 300 écran verrouillé, 400 centre de notifications sur l'écran verrouillé.
    /// Il faut 400 pour passer au-dessus de l'écran verrouillé (100 restait dessous).
    private static let absoluteLevel: Int32 = 400

    private let connection: Int32
    private let spaceCreate: SpaceCreate
    private let setAbsoluteLevel: SpaceSetAbsoluteLevel
    private let showSpaces: ShowSpaces
    private let addWindows: AddWindowsToSpace
    private var space: UInt64 = 0

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return nil
        }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let mainConnection = load("SLSMainConnectionID", as: MainConnectionID.self),
              let spaceCreate = load("SLSSpaceCreate", as: SpaceCreate.self),
              let setAbsoluteLevel = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let showSpaces = load("SLSShowSpaces", as: ShowSpaces.self),
              let addWindows = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsToSpace.self)
        else { return nil }
        connection = mainConnection()
        self.spaceCreate = spaceCreate
        self.setAbsoluteLevel = setAbsoluteLevel
        self.showSpaces = showSpaces
        self.addWindows = addWindows
    }

    /// Place la fenêtre dans l'espace de niveau supérieur (créé une seule fois). Sans effet si elle y est déjà.
    func pin(_ window: NSWindow) {
        if space == 0 {
            space = spaceCreate(connection, 1, 0)
            guard space != 0 else {
                spaceLog.error("création de l'espace SkyLight impossible")
                return
            }
            let level = setAbsoluteLevel(connection, space, Self.absoluteLevel)
            let shown = showSpaces(connection, [NSNumber(value: space)] as CFArray)
            spaceLog.notice("espace \(self.space) créé · niveau \(level) · affichage \(shown)")
        }
        move(window, to: space)
    }

    private func move(_ window: NSWindow, to space: UInt64) {
        // 7 : retire la fenêtre de tous ses espaces actuels avant de l'ajouter.
        let result = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        spaceLog.notice("fenêtre \(window.windowNumber) → espace \(space) · résultat \(result)")
    }
}
