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

struct SliderLayoutTests {
    @Test func zoneCliquableJamaisPlusFineQueLeMinimum() {
        #expect(NotchLayout.sliderHitHeight(for: 14) == NotchLayout.sliderMinimumHitHeight)
        #expect(NotchLayout.sliderHitHeight(for: 26) == 26)
    }

    @Test func pastilleResteDansLeRail() {
        #expect(NotchLayout.sliderKnobCenter(fraction: 0, trackWidth: 200, knobWidth: 40) == 20)
        #expect(NotchLayout.sliderKnobCenter(fraction: 1, trackWidth: 200, knobWidth: 40) == 180)
        #expect(NotchLayout.sliderFraction(atX: 100, trackWidth: 200, knobWidth: 40) == 0.5)
        #expect(NotchLayout.sliderFraction(atX: -10, trackWidth: 200, knobWidth: 40) == 0)
        let resting = NotchLayout.sliderKnobSize(for: 26, isDragging: false)
        let dragging = NotchLayout.sliderKnobSize(for: 26, isDragging: true)
        #expect(dragging.height > resting.height)
        #expect(NotchLayout.sliderTrackThickness(for: 26) < resting.height)
    }
}
