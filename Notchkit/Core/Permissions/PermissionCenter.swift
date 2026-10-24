import AppKit
import ApplicationServices
import AVFoundation
import CoreLocation
import EventKit
import Observation
import SwiftUI

/// Autorisation macOS dont Notchkit peut avoir besoin, avec ce qu'elle débloque.
enum AppPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case systemAudio
    case automation
    case calendars
    case reminders
    case camera
    case location
    case screenRecording

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .accessibility: "Accessibilité"
        case .systemAudio: "Enregistrement audio du système"
        case .automation: "Automatisation"
        case .calendars: "Calendriers"
        case .reminders: "Rappels"
        case .camera: "Caméra"
        case .location: "Localisation"
        case .screenRecording: "Enregistrement de l'écran"
        }
    }

    /// Nom court (mosaïque du tutoriel).
    var shortTitle: LocalizedStringResource {
        self == .systemAudio ? "Audio du système" : title
    }

    /// Fonctions qui en dépendent (affiché sous le titre).
    var usage: LocalizedStringResource {
        switch self {
        case .accessibility:
            "Volume et luminosité aux touches du clavier, encoche qui évite les menus, traduction de la sélection, verrouillage du clavier."
        case .systemAudio:
            "Barres de l'égaliseur au rythme de la musique et volume par app. Le son n'est jamais enregistré."
        case .automation:
            "Commandes de Musique et Spotify, et mode sombre (System Events)."
        case .calendars:
            "Prochains événements dans l'encoche et rappel quelques minutes avant."
        case .reminders:
            "Liste de rappels : les cocher ou en ajouter."
        case .camera:
            "Miroir de la webcam, seulement pendant que le widget est ouvert. Rien n'est enregistré."
        case .location:
            "Météo locale, à partir d'une position approximative."
        case .screenRecording:
            "Images par seconde du jeu en cours, en mode jeu. L'écran n'est jamais enregistré."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .systemAudio: "waveform"
        case .automation: "gearshape.2.fill"
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .camera: "camera.fill"
        case .location: "location.fill"
        case .screenRecording: "record.circle"
        }
    }

    var color: Color {
        switch self {
        case .accessibility: .blue
        case .systemAudio: .pink
        case .automation: .gray
        case .calendars: .red
        case .reminders: .orange
        case .camera: .green
        case .location: .cyan
        case .screenRecording: .purple
        }
    }

    /// Volet des Réglages Système (Confidentialité et sécurité).
    var settingsURL: URL? {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .systemAudio: "Privacy_AudioCapture"
        case .automation: "Privacy_Automation"
        case .calendars: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .camera: "Privacy_Camera"
        case .location: "Privacy_LocationServices"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

/// État d'une autorisation.
enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    /// macOS ne permet pas de lire l'état (audio du système, automatisation) : demandée à la première utilisation.
    case onFirstUse

    var label: LocalizedStringResource {
        switch self {
        case .granted: "Autorisée"
        case .denied: "Refusée"
        case .notDetermined: "Pas encore demandée"
        case .onFirstUse: "Demandée à la première utilisation"
        }
    }

    // MARK: Conversions (fonctions pures, testées)

    static func from(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func from(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func from(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

/// Synthèse des autorisations : état en direct, demande, accès aux Réglages Système.
@MainActor
@Observable
final class PermissionCenter {
    private(set) var states: [AppPermission: PermissionState] = [:]

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private lazy var location: LocationProvider = {
        let provider = LocationProvider()
        provider.onAuthorizationChange = { [weak self] in self?.refresh() }
        return provider
    }()

    init() {
        refresh()
    }

    func state(of permission: AppPermission) -> PermissionState {
        states[permission] ?? .onFirstUse
    }

    var grantedCount: Int {
        AppPermission.allCases.filter { state(of: $0) == .granted }.count
    }

    func refresh() {
        var next: [AppPermission: PermissionState] = [:]
        for permission in AppPermission.allCases {
            next[permission] = currentState(of: permission)
        }
        if next != states { states = next }
    }

    private func currentState(of permission: AppPermission) -> PermissionState {
        switch permission {
        // Un refus d'Accessibilité ne se distingue pas d'une absence de demande.
        case .accessibility: AXIsProcessTrusted() ? .granted : .notDetermined
        case .systemAudio, .automation: .onFirstUse
        case .calendars: .from(EKEventStore.authorizationStatus(for: .event))
        case .reminders: .from(EKEventStore.authorizationStatus(for: .reminder))
        case .camera: .from(AVCaptureDevice.authorizationStatus(for: .video))
        case .location: .from(location.status)
        case .screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        }
    }

    /// Demande l'autorisation (fenêtre de macOS) ; si macOS ne la propose plus, ouvre les Réglages Système.
    func request(_ permission: AppPermission) {
        guard state(of: permission) == .notDetermined else { return openSettings(permission) }
        switch permission {
        case .accessibility:
            MediaKeyTap.requestTrust()
            openSettings(permission)
        case .calendars:
            NSApp.activate()
            eventStore.requestFullAccessToEvents { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
            }
        case .reminders:
            NSApp.activate()
            eventStore.requestFullAccessToReminders { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
            }
        case .camera:
            NSApp.activate()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
            }
        case .location:
            location.requestAuthorization()
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings(permission) }
        case .systemAudio, .automation:
            openSettings(permission)
        }
    }

    func openSettings(_ permission: AppPermission) {
        Self.open(permission)
    }

    static func open(_ permission: AppPermission) {
        if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
    }
}
