import SwiftUI

/// Alerte temporaire affichée dans l'encoche repliée (ex. « chargeur branché »).
/// Elle prend le pas sur le module compact pendant `duration`, puis disparaît.
struct NotchAlert: Identifiable {
    let id = UUID()
    let leading: AnyView
    let trailing: AnyView
    var duration: Duration = .seconds(2.5)
    /// Alerte « agrandie » (façon Dynamic Island) : contenu centré sous l'encoche, à cette taille.
    var expandedContent: AnyView?
    var expandedSize: CGSize?
    /// Module ouvert si l'on survole l'encoche pendant l'alerte (ex. l'indicateur de volume mène au centre du son).
    var openModuleID: String?
    /// Largeur de chaque côté de l'encoche (`nil` : celle de la musique, `NotchLayout.compactSideWidth`).
    var sideWidth: CGFloat?

    init(leading: AnyView = AnyView(EmptyView()), trailing: AnyView = AnyView(EmptyView()),
         duration: Duration = .seconds(2.5),
         expandedContent: AnyView? = nil, expandedSize: CGSize? = nil) {
        self.leading = leading
        self.trailing = trailing
        self.duration = duration
        self.expandedContent = expandedContent
        self.expandedSize = expandedSize
    }
}
