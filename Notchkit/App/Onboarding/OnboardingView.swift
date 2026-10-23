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
    private let viewModel: NotchViewModel
    private let openSettings: @MainActor (SettingsTab) -> Void

    init(settings: SettingsStore, manager: ModuleManager, viewModel: NotchViewModel,
         openSettings: @escaping @MainActor (SettingsTab) -> Void) {
        self.settings = settings
        self.manager = manager
        self.viewModel = viewModel
        self.openSettings = openSettings
    }

    func show() {
        if window == nil {
            let view = OnboardingView(
                manager: manager,
                viewModel: viewModel,
                mascot: settings.settings.mascot,
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
    let viewModel: NotchViewModel
    let mascot: MascotDesign
    let openSettings: (SettingsTab) -> Void
    let finish: () -> Void

    @State private var step: OnboardingStep
    @State private var permissions = PermissionCenter()
    /// Avance (vers la droite) ou recule : sens de la transition entre étapes.
    @State private var isForward = true

    init(manager: ModuleManager, viewModel: NotchViewModel, mascot: MascotDesign,
         openSettings: @escaping (SettingsTab) -> Void, finish: @escaping () -> Void,
         startAt step: OnboardingStep = .welcome) {
        self.manager = manager
        self.viewModel = viewModel
        self.mascot = mascot
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
        case .agents: AgentsDemo(mascot: mascot)
        case .widgets: SymbolDemo(symbol: "square.grid.2x2.fill", tint: StandBy.defaultAccent.color)
        case .permissions: PermissionsDemo(center: permissions)
        case .tryIt: TryItDemo()
        case .done: SymbolDemo(symbol: "checkmark.circle.fill", tint: .green)
        }
    }

    // MARK: Contrôles propres à l'étape

    @ViewBuilder
    private var controls: some View {
        switch step {
        case .widgets: OnboardingPresets(manager: manager, openLayoutSettings: { openSettings(.layout) })
        case .agents: OnboardingAgents(manager: manager)
        case .permissions: OnboardingPermissions(center: permissions, openDetails: { openSettings(.permissions) })
        case .tryIt: OnboardingTrial(viewModel: viewModel, manager: manager)
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
                    Button("Demander l'accès…") { center.request(.accessibility) }
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

// MARK: - Agents

/// Affiche la page Agents (masquée par défaut) d'un clic.
private struct OnboardingAgents: View {
    let manager: ModuleManager

    private var isShown: Bool { manager.isEnabled(AgentsModule.descriptor.id) }

    var body: some View {
        if isShown {
            Label("Page Agents affichée", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        } else {
            Button("Afficher la page Agents") {
                withAnimation(.snappy) { manager.setEnabled(true, for: AgentsModule.descriptor.id) }
            }
            .buttonStyle(.standBy(.small, active: true))
        }
    }
}

// MARK: - Essai guidé

/// Essai guidé : gestes à faire sur la vraie encoche, cochés dès qu'ils sont détectés.
private struct OnboardingTrial: View {
    let viewModel: NotchViewModel
    let manager: ModuleManager

    @State private var done: Set<OnboardingTrialTask> = []
    /// Minuteur d'essai lancé depuis le tutoriel (retiré en quittant l'étape).
    @State private var timerID: String?
    @State private var sampleFile: URL?

    private var shelf: ShelfModule? { manager.module(for: ShelfModule.descriptor.id) as? ShelfModule }
    private var timers: LiveActivitiesModule? { manager.module(for: LiveActivitiesModule.descriptor.id) as? LiveActivitiesModule }
    private var tasks: [OnboardingTrialTask] {
        OnboardingTrialTask.available(pageCount: ModulePage.pages(from: manager).count,
                                      hasShelf: shelf != nil, hasTimers: timers != nil)
    }
    private var trialTimer: LiveActivity? { timers?.activities.first { $0.id == timerID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tasks) { task in row(task) }
            if tasks.allSatisfy(done.contains) {
                Label("Bravo, vous savez tout faire !", systemImage: "party.popper.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 440)
        .onChange(of: viewModel.isExpanded) { _, open in if open { mark(.open) } }
        .onChange(of: viewModel.selectedPage) { _, _ in if viewModel.isExpanded { mark(.swipe) } }
        .onChange(of: shelf?.items.count ?? 0) { old, new in if new > old { mark(.drop) } }
        .onChange(of: trialTimer?.isPaused ?? false) { _, paused in if paused { mark(.pause) } }
        .onChange(of: trialTimer == nil) { _, gone in if gone { timerID = nil } }
        .onDisappear {
            if let timerID { timers?.remove(timerID) }
        }
    }

    private func row(_ task: OnboardingTrialTask) -> some View {
        let isDone = done.contains(task)
        return HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isDone ? Color.green : Color.white.opacity(0.4))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(isDone, color: .white.opacity(0.5))
                Text(task.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !isDone { accessory(task) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(.white.opacity(isDone ? 0.03 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? Text("Fait") : Text("À faire"))
    }

    @ViewBuilder
    private func accessory(_ task: OnboardingTrialTask) -> some View {
        switch task {
        case .drop:
            // Fichier d'essai à faire glisser sur l'encoche.
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill").foregroundStyle(.white)
                Text(verbatim: sampleName).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay { FileDragSource(file: makeSampleFile) }
            .help(Text("Faites glisser ce fichier sur l'encoche"))
        case .pause where timerID == nil:
            Button("Lancer") {
                guard let timers else { return }
                timers.startTimer(minutes: 2, title: String(localized: "Essai"))
                timerID = timers.activities.last?.id
            }
            .buttonStyle(.standBy(.small, active: true))
        default:
            EmptyView()
        }
    }

    private var sampleName: String { String(localized: "Essai Notchkit.txt") }

    /// Fichier texte créé dans le dossier temporaire, au premier glisser.
    private func makeSampleFile() -> URL {
        if let sampleFile { return sampleFile }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(sampleName)
        try? String(localized: "Ce fichier vient du tutoriel de Notchkit. Vous pouvez le supprimer.")
            .write(to: url, atomically: true, encoding: .utf8)
        sampleFile = url
        return url
    }

    private func mark(_ task: OnboardingTrialTask) {
        guard tasks.contains(task), !done.contains(task) else { return }
        withAnimation(.snappy) { _ = done.insert(task) }
        Haptics.play(.tap)
    }
}

/// Source de glisser AppKit pour un fichier : publie son URL comme le Finder, et se déclare acceptée
/// par l'encoche, qui refuse sinon les glissers venus de Notchkit.
private struct FileDragSource: NSViewRepresentable {
    let file: () -> URL

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        view.file = file
        return view
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        view.file = file
    }
}

private final class FileDragSourceView: NSView, NSDraggingSource, AcceptedInternalDragSource {
    var file: (() -> URL)?
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let url = file?() else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let origin = convert(start.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: origin.x - 16, y: origin.y - 16, width: 32, height: 32), contents: icon)
        beginDraggingSession(with: [item], event: start, source: self)
        // Glisser parti de Notchkit : le moniteur global de DropCatcher ne le voit pas.
        NotificationCenter.default.post(name: DropCatcher.internalDragDidStart, object: nil)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.copy, .generic]
    }
}
