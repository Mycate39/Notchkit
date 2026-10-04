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
    /// Alerte « agrandie » (façon Dynamic Island) : contenu centré sous l'encoche, à cette taille.
    var expandedContent: AnyView?
    var expandedSize: CGSize?

    init(leading: AnyView = AnyView(EmptyView()), trailing: AnyView = AnyView(EmptyView()),
         duration: Duration = .seconds(2.5), sideWidth: CGFloat? = nil,
         expandedContent: AnyView? = nil, expandedSize: CGSize? = nil) {
        self.leading = leading
        self.trailing = trailing
        self.duration = duration
        self.sideWidth = sideWidth
        self.expandedContent = expandedContent
        self.expandedSize = expandedSize
    }
}
