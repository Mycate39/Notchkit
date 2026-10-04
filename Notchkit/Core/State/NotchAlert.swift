import SwiftUI

/// Alerte temporaire affichée dans l'encoche repliée (ex. « chargeur branché »).
/// Elle prend le pas sur le module compact pendant `duration`, puis disparaît.
struct NotchAlert: Identifiable {
    let id = UUID()
    let leading: AnyView
    let trailing: AnyView
    var duration: Duration = .seconds(2.5)
    /// Largeur de chaque côté de l'encoche (plus large pour l'indicateur de volume, par exemple).
    var sideWidth: CGFloat?
}
