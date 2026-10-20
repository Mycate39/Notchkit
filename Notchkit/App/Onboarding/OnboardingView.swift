import AppKit
import ApplicationServices
import SwiftUI

/// Fenêtre du tutoriel de bienvenue (premier lancement, ou menu « Revoir le tutoriel »).
/// La fermer, par le bouton rouge ou à la dernière étape, marque le tutoriel comme vu.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let manager: ModuleManager
    private let openSettings: @MainActor (SettingsTab) -> Void

    init(settings: SettingsStore, manager: ModuleManager, openSettings: @escaping @MainActor (SettingsTab) -> Void) {
        self.settings = settings
        self.manager = manager
        self.openSettings = openSettings
    }

    func show() {
        if window == nil {
            let view = OnboardingView(
                manager: manager,
                openSettings: { [weak self] tab in self?.openSettings(tab) },
                finish: { [weak self] in self?.window?.close() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "Bienvenue dans Notchkit")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        settings.settings.onboardingCompleted = true
        // Vue recréée à la prochaine ouverture : le tutoriel repart de la première étape.
        window = nil
    }
}

/// Contenu du tutoriel : démonstration, texte, contrôles de l'étape, navigation.
struct OnboardingView: View {
    let manager: ModuleManager
    let openSettings: (SettingsTab) -> Void
    let finish: () -> Void

    @State private var step: OnboardingStep
    @State private var permissions = PermissionCenter()
    /// Avance (vers la droite) ou recule : sens de la transition entre étapes.
    @State private var isForward = true

    init(manager: ModuleManager, openSettings: @escaping (SettingsTab) -> Void, finish: @escaping () -> Void,
         startAt step: OnboardingStep = .welcome) {
        self.manager = manager
        self.openSettings = openSettings
        self.finish = finish
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            demo
                .padding(.top, 36)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)))

            VStack(spacing: 10) {
                Text(step.title)
                    .font(.system(size: 22, weight: .bold))
                Text(step.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
                controls
                    .padding(.top, 6)
            }
            .padding(.top, 22)
            .padding(.horizontal, 32)
            .id(step)
            .transition(.opacity)

            Spacer(minLength: 16)
            navigation
        }
        .frame(width: 560, height: 560)
        .background(Color(white: 0.08))
        .tint(StandBy.defaultAccent.color)
    }

    // MARK: Illustration

    @ViewBuilder
    private var demo: some View {
        switch step {
        case .welcome: WelcomeDemo()
        case .hover: HoverDemo()
        case .activities: ActivitiesDemo()
        case .files: FilesDemo()
        case .widgets: SymbolDemo(symbol: "square.grid.2x2.fill", tint: StandBy.defaultAccent.color)
        case .permissions: PermissionsDemo(center: permissions)
        case .done: SymbolDemo(symbol: "checkmark.circle.fill", tint: .green)
        }
    }

    // MARK: Contrôles propres à l'étape

    @ViewBuilder
    private var controls: some View {
        switch step {
        case .widgets: OnboardingPresets(manager: manager, openLayoutSettings: { openSettings(.layout) })
        case .permissions: OnboardingPermissions(center: permissions, openDetails: { openSettings(.permissions) })
        default: EmptyView()
        }
    }

    // MARK: Navigation

    private var navigation: some View {
        HStack {
            if step.isLast {
                Spacer()
            } else {
                Button("Passer le tutoriel", action: finish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { item in
                    Circle()
                        .fill(item == step ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Spacer()

            HStack(spacing: 8) {
                if let previous = step.previous {
                    Button("Retour") { go(to: previous, forward: false) }
                        .buttonStyle(.standBy(.small))
                }
                if let next = step.next {
                    Button("Continuer") { go(to: next, forward: true) }
                        .buttonStyle(.standBy(.small, active: true))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Commencer", action: finish)
                        .buttonStyle(.standBy(.small, active: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func go(to target: OnboardingStep, forward: Bool) {
        isForward = forward
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { step = target }
    }
}

// MARK: - Dispositions

/// Choix d'une disposition prête à l'emploi, appliquée tout de suite (annulable dans les réglages).
private struct OnboardingPresets: View {
    let manager: ModuleManager
    let openLayoutSettings: () -> Void
    @State private var applied: String?

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(LayoutPreset.all) { preset in
                        Button {
                            withAnimation(.snappy) {
                                manager.apply(preset)
                                applied = preset.id
                            }
                        } label: {
                            PresetCard(preset: preset)
                                .overlay(alignment: .topTrailing) {
                                    if applied == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.green)
                                            .padding(6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxWidth: 500)

            Button("Personnaliser dans les réglages…", action: openLayoutSettings)
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Autorisations

/// Accessibilité (la plus utile, à donner tout de suite), lien vers le détail et lancement à l'ouverture de session.
private struct OnboardingPermissions: View {
    let center: PermissionCenter
    let openDetails: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    private var isTrusted: Bool { center.state(of: .accessibility) == .granted }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PermissionIcon(permission: .accessibility, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibilité")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isTrusted ? "Autorisée" : "Recommandée : touches du clavier et menus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isTrusted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                } else {
                    Button("Autoriser…") { center.request(.accessibility) }
                        .buttonStyle(.standBy(.small))
                }
            }
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    Text("Lancer à l'ouverture de session")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Button("Détail des autorisations…", action: openDetails)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)

            if let launchError {
                Text(launchError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 440)
        // Les autorisations se donnent dans les Réglages Système : on suit leur état en direct.
        .task {
            while !Task.isCancelled {
                center.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchError = LaunchAtLogin.setEnabled(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
