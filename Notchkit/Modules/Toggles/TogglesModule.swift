import AppKit
import SwiftUI
import Observation

/// Module Commutateurs rapides : mode sombre, anti-veille, icônes du bureau et nettoyage du clavier.
@MainActor
@Observable
final class TogglesModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "toggles",
        name: "Commutateurs rapides",
        summary: "Mode sombre, anti-veille, icônes du bureau et verrouillage du clavier pour le nettoyer.",
        systemImage: "switch.2",
        category: .system,
        tier: .free,
        defaultEnabled: false
    )

    /// Durée maximale du verrouillage du clavier (sécurité : il se libère de lui-même).
    static let cleaningDuration: TimeInterval = 60

    private(set) var isDarkMode = DarkMode.isOn
    private(set) var isAntiSleepOn = false
    private(set) var areDesktopIconsVisible = DesktopIcons.areVisible
    private(set) var cleaningEndsAt: Date?
    private(set) var needsAccessibility = false

    var isCleaning: Bool { cleaningEndsAt != nil }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let sleepPreventer = SleepPreventer()
    @ObservationIgnored private let keyboardLock = KeyboardCleaningLock()
    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?
    @ObservationIgnored private var cleaningTask: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        // Mode sombre changé ailleurs (Réglages Système, Centre de contrôle) : on suit.
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isDarkMode = DarkMode.isOn }
        }
    }

    func stop() {
        if let appearanceObserver { DistributedNotificationCenter.default().removeObserver(appearanceObserver) }
        appearanceObserver = nil
        sleepPreventer.setActive(false)
        isAntiSleepOn = false
        stopCleaning()
    }

    // MARK: Actions

    func toggleDarkMode() {
        let target = !isDarkMode
        if DarkMode.set(target) { withAnimation(.snappy) { isDarkMode = target } }
    }

    func toggleAntiSleep() {
        sleepPreventer.setActive(!isAntiSleepOn)
        withAnimation(.snappy) { isAntiSleepOn = sleepPreventer.isActive }
    }

    func toggleDesktopIcons() {
        let target = !areDesktopIconsVisible
        DesktopIcons.setVisible(target)
        withAnimation(.snappy) { areDesktopIconsVisible = target }
    }

    /// Verrouille le clavier pour le nettoyer (60 s au plus) ; déverrouillage depuis l'encoche.
    func startCleaning() {
        guard keyboardLock.lock() else {
            needsAccessibility = true
            MediaKeyTap.requestTrust()
            return
        }
        needsAccessibility = false
        let end = Date().addingTimeInterval(Self.cleaningDuration)
        withAnimation(.snappy) { cleaningEndsAt = end }
        context.holdExpanded(true)
        cleaningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.cleaningDuration))
            guard !Task.isCancelled else { return }
            self?.stopCleaning()
        }
    }

    func stopCleaning() {
        cleaningTask?.cancel()
        cleaningTask = nil
        keyboardLock.unlock()
        guard cleaningEndsAt != nil else { return }
        withAnimation(.snappy) { cleaningEndsAt = nil }
        context.holdExpanded(false)
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { isCleaning ? .high : .none }

    func compactLeading() -> AnyView? {
        guard isCleaning else { return nil }
        return AnyView(Image(systemName: "keyboard.badge.ellipsis").foregroundStyle(StandBy.amber))
    }

    func compactTrailing() -> AnyView? {
        guard let end = cleaningEndsAt else { return nil }
        return AnyView(Text(timerInterval: Date()...end, countsDown: true).monospacedDigit().foregroundStyle(StandBy.amber))
    }

    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "switch.2", value: nil, caption: String(localized: "Commutateurs")))
    }

    func expandedView() -> AnyView {
        AnyView(TogglesExpandedView(module: self))
    }
}
