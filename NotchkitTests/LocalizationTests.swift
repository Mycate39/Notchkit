import Foundation
import Testing
@testable import Notchkit

/// L'app suit la langue du Mac : les tables anglaise ET française doivent être présentes et complètes.
/// (Sans valeur française explicite dans le catalogue, Xcode ne produit pas de table française,
/// et un Mac en français retombe sur l'anglais.)
struct LocalizationTests {
    private func table(_ language: String) -> [String: String]? {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                          inDirectory: nil, forLocalization: language)
        else { return nil }
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }

    @Test func tablesFrancaiseEtAnglaiseCompletes() throws {
        let french = try #require(table("fr"))
        let english = try #require(table("en"))
        #expect(!french.isEmpty)
        #expect(Set(french.keys) == Set(english.keys))
        #expect(french["Aucune lecture en cours"] == "Aucune lecture en cours")
        #expect(english["Aucune lecture en cours"] == "Nothing playing")
    }
}
