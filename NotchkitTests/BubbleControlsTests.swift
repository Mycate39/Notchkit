import Foundation
import SwiftUI
import Testing
@testable import Notchkit

@MainActor
@Observable
final class MockPrimaryModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.primary", name: "P", summary: "", systemImage: "p.circle",
        category: .widgets, tier: .free, defaultEnabled: true
    )
    var compactPriority: ModulePriority { .high }
    init(context: ModuleContext) {}
    func compactLeading() -> AnyView? { AnyView(Text(verbatim: "P")) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
@Observable
final class MockControlsModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.controls", name: "C", summary: "", systemImage: "c.circle",
        category: .media, tier: .free, defaultEnabled: true
    )
    var compactPriority: ModulePriority { .normal }
    init(context: ModuleContext) {}
    func compactLeading() -> AnyView? { AnyView(Text(verbatim: "C")) }
    func bubbleControls() -> AnyView? { AnyView(Text(verbatim: "▶︎")) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
@Observable
final class MockClickOnlyModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.click", name: "K", summary: "", systemImage: "k.circle",
        category: .widgets, tier: .free, defaultEnabled: false
    )
    var compactPriority: ModulePriority { .normal }
    var bubbleOpensOnHover: Bool { false }
    init(context: ModuleContext) {}
    func compactLeading() -> AnyView? { AnyView(Text(verbatim: "K")) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

/// Commandes qui sortent à droite d'une bulle (musique) au survol, sans déplier l'encoche.
@MainActor
struct BubbleControlsTests {
    private func makeViewModel() -> NotchViewModel {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(),
                                    availableModules: [MockPrimaryModule.self, MockControlsModule.self, MockClickOnlyModule.self])
        manager.reload()
        return NotchViewModel(manager: manager, settings: settings)
    }

    private func wait() async { try? await Task.sleep(for: .seconds(NotchLayout.bubbleControlsCloseDelay + 0.15)) }

    @Test func commandesAuSurvolSansDeplierLEncoche() async {
        let viewModel = makeViewModel()
        #expect(viewModel.bubbleModules.map(\.moduleID) == ["mock.controls"])
        let closedWidth = viewModel.panelSize.width

        viewModel.hoverBubbleControls("mock.controls", part: .bubble, inside: true)
        await wait()
        #expect(viewModel.bubbleControlsID == "mock.controls")
        #expect(!viewModel.isExpanded)
        // La fenêtre s'élargit des deux côtés pour accueillir les commandes.
        let extra = NotchLayout.bubbleControlsContentWidth
        #expect(viewModel.panelSize.width == closedWidth + extra * 2)

        // De la bulle aux commandes (entrée avant ou après la sortie) : elles restent sorties.
        viewModel.hoverBubbleControls("mock.controls", part: .controls, inside: true)
        viewModel.hoverBubbleControls("mock.controls", part: .bubble, inside: false)
        await wait()
        #expect(viewModel.bubbleControlsID == "mock.controls")

        // La souris s'en va : elles rentrent.
        viewModel.hoverBubbleControls("mock.controls", part: .controls, inside: false)
        await wait()
        #expect(viewModel.bubbleControlsID == nil)
        #expect(viewModel.panelSize.width == closedWidth)
    }

    @Test func ouvrirLEncocheRentreLesCommandes() async {
        let viewModel = makeViewModel()
        viewModel.hoverBubbleControls("mock.controls", part: .bubble, inside: true)
        await wait()
        viewModel.expand(showing: "mock.controls")
        #expect(viewModel.bubbleControlsID == nil)
        viewModel.collapse()
    }

    @Test func minuteurAvecPauseEtArret() {
        let module = LiveActivitiesModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
        #expect(module.bubbleControls() == nil)
        module.startTimer(minutes: 5)
        #expect(module.bubbleControls() != nil)
        // Deux boutons et le temps restant (moins d'une heure : « 4:59 »).
        #expect(module.bubbleControlsWidth == NotchLayout.timerBubbleControlsWidth(showsHours: false))
        #expect(NotchLayout.timerBubbleControlsWidth(showsHours: true) > module.bubbleControlsWidth)
        let id = try! #require(module.mostRelevant?.id)
        module.togglePause(id)
        // En pause : la bulle et ses commandes restent (pour reprendre).
        #expect(module.compactPriority == .normal)
        #expect(module.bubbleControls() != nil)
        module.remove(id)
        #expect(module.compactPriority == .none)
    }

    @Test func musiqueEnPauseGardeSaBulle() {
        let music = MusicModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
        music.debugSetNowPlaying(NowPlayingInfo(origin: .mediaRemote, title: "Get Lucky", isPlaying: false))
        // En pause : pas d'activité dans l'encoche, mais la bulle reste.
        #expect(music.compactPriority == .none)
        #expect(music.bubblePriority == .normal)
        #expect(music.bubbleControls() != nil)
        music.debugSetNowPlaying(nil)
        #expect(music.bubblePriority == .none)
    }

    @Test func musiqueEnLecturePasseDevantLesActivites() {
        let music = MusicModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
        music.debugSetNowPlaying(NowPlayingInfo(origin: .mediaRemote, title: "Get Lucky", isPlaying: true))
        // Devant Claude Code qui travaille et les minuteurs, derrière une information urgente.
        #expect(music.compactPriority > .elevated)
        #expect(music.compactPriority < .high)
        #expect(music.bubblePriority == music.compactPriority)
        // Claude Code qui attend une autorisation reste dans une bulle à côté de la musique en lecture.
        #expect(music.compactPriority > .urgentActivity && ModulePriority.urgentActivity > .elevated)
        music.debugSetNowPlaying(nil)
    }

    @Test func bulleQuiNeSOuvreQuAuClic() async {
        let viewModel = makeViewModel()
        viewModel.manager.setEnabled(true, for: "mock.click")
        viewModel.hoverBubble("mock.click", inside: true)
        // Bien au-delà du délai d'ouverture au survol.
        try? await Task.sleep(for: .seconds(1.5))
        #expect(!viewModel.isExpanded)
        viewModel.hoverBubble("mock.click", inside: false)
    }
}
