import Foundation
import Testing
@testable import Notchkit

struct UnlockTests {
    @Test func composantsDAuthentificationReconnus() {
        #expect(AuthPrompt(bundleIdentifier: "com.apple.SecurityAgent") == .password)
        #expect(AuthPrompt(bundleIdentifier: "com.apple.LocalAuthentication.UIAgent") == .touchID)
        #expect(AuthPrompt(bundleIdentifier: "com.apple.Safari") == nil)
        #expect(AuthPrompt(bundleIdentifier: nil) == nil)
    }

    @Test func alerteAgrandieChangeLaTailleDeLEncoche() {
        let geometry = NotchGeometry(style: .pill, closedSize: CGSize(width: 96, height: 20), screenFrame: .zero, centerX: 0)
        let size = NotchLayout.shapeSize(for: geometry, isExpanded: false, hasCompactContent: true, alertSize: UnlockAnimations.size)
        #expect(size == UnlockAnimations.size)
        // Dépliée, l'encoche garde sa taille normale.
        let expanded = NotchLayout.shapeSize(for: geometry, isExpanded: true, hasCompactContent: true, alertSize: UnlockAnimations.size)
        #expect(expanded.width == NotchLayout.expandedSize.width)
    }
}
