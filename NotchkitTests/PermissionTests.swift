import AVFoundation
import CoreLocation
import EventKit
import Testing
@testable import Notchkit

struct PermissionTests {
    @Test func etatsDesCalendriersEtRappels() {
        #expect(PermissionState.from(EKAuthorizationStatus.fullAccess) == .granted)
        #expect(PermissionState.from(EKAuthorizationStatus.notDetermined) == .notDetermined)
        // Accès en écriture seule : insuffisant pour lire les événements.
        #expect(PermissionState.from(EKAuthorizationStatus.writeOnly) == .denied)
        #expect(PermissionState.from(EKAuthorizationStatus.denied) == .denied)
    }

    @Test func etatsDeLaCameraEtDeLaLocalisation() {
        #expect(PermissionState.from(AVAuthorizationStatus.authorized) == .granted)
        #expect(PermissionState.from(AVAuthorizationStatus.restricted) == .denied)
        #expect(PermissionState.from(CLAuthorizationStatus.authorizedAlways) == .granted)
        #expect(PermissionState.from(CLAuthorizationStatus.notDetermined) == .notDetermined)
    }

    @Test func chaqueAutorisationOuvreSonVoletDesReglages() {
        for permission in AppPermission.allCases {
            let url = try? #require(permission.settingsURL)
            #expect(url?.absoluteString.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_") == true)
        }
    }
}
