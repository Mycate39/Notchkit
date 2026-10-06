import AppKit

/// Affiche l'encoche sur l'écran de verrouillage.
///
/// ⚠️ API privée (SkyLight), acceptée uniquement pour cet usage. Aucune interface publique ne permet
/// d'afficher une fenêtre au-dessus de l'écran verrouillé : on place le panneau dans un « espace »
/// SkyLight de niveau supérieur pendant le verrouillage, puis on le rend à l'espace actif au
/// déverrouillage. Les fonctions sont chargées dynamiquement : si l'une manque (mise à jour de
/// macOS), `init` échoue et l'encoche reste simplement invisible écran verrouillé.
@MainActor
final class LockScreenSpace {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias GetActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias AddWindowsToSpace = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    /// Niveau de l'espace : au-dessus de l'écran de verrouillage.
    private static let absoluteLevel: Int32 = 100

    private let connection: Int32
    private let spaceCreate: SpaceCreate
    private let setAbsoluteLevel: SpaceSetAbsoluteLevel
    private let showSpaces: ShowSpaces
    private let activeSpace: GetActiveSpace
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
              let activeSpace = load("SLSGetActiveSpace", as: GetActiveSpace.self),
              let addWindows = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsToSpace.self)
        else { return nil }
        connection = mainConnection()
        self.spaceCreate = spaceCreate
        self.setAbsoluteLevel = setAbsoluteLevel
        self.showSpaces = showSpaces
        self.activeSpace = activeSpace
        self.addWindows = addWindows
    }

    /// Écran verrouillé : la fenêtre passe dans l'espace de niveau supérieur (créé une seule fois).
    func moveToLockScreen(_ window: NSWindow) {
        if space == 0 {
            space = spaceCreate(connection, 1, 0)
            guard space != 0 else { return }
            _ = setAbsoluteLevel(connection, space, Self.absoluteLevel)
            _ = showSpaces(connection, [NSNumber(value: space)] as CFArray)
        }
        move(window, to: space)
    }

    /// Déverrouillage : la fenêtre revient dans l'espace (bureau) actif.
    func moveBack(_ window: NSWindow) {
        let active = activeSpace(connection)
        guard active != 0 else { return }
        move(window, to: active)
    }

    private func move(_ window: NSWindow, to space: UInt64) {
        // 7 : retire la fenêtre de tous ses espaces actuels avant de l'ajouter.
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}
