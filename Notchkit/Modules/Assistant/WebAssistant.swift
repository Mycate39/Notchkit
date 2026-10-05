import AppKit
import SwiftUI
import WebKit

/// Assistant utilisé via son site officiel : on s'y connecte avec son compte (et son abonnement).
enum WebAssistantService: String, CaseIterable, Identifiable, Codable, Sendable {
    case chatGPT, gemini, grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }

    var url: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com/")!
        case .gemini: URL(string: "https://gemini.google.com/app")!
        case .grok: URL(string: "https://grok.com/")!
        }
    }

    /// Pictogramme neutre (pas de logo de marque).
    var symbol: String {
        switch self {
        case .chatGPT: "bubble.left.and.text.bubble.right"
        case .gemini: "sparkle"
        case .grok: "bolt.horizontal.circle"
        }
    }
}

/// Fenêtre flottante sous l'encoche qui affiche le site de l'assistant choisi.
///
/// Les cookies sont conservés (magasin de données persistant de WebKit) : on reste connecté
/// d'une ouverture à l'autre. Une page par service, gardée en mémoire tant que l'app tourne,
/// pour retrouver la conversation en cours.
@MainActor
final class WebAssistantWindowController: NSObject, NSWindowDelegate {
    static let shared = WebAssistantWindowController()

    /// Taille par défaut de la fenêtre.
    static let defaultSize = NSSize(width: 440, height: 640)

    private var panel: NSPanel?
    private var webViews: [WebAssistantService: WKWebView] = [:]
    private let state = WebAssistantState()

    /// Ouvre (ou ferme, si elle montre déjà ce service) la fenêtre sous l'encoche.
    func toggle(_ service: WebAssistantService) {
        if let panel, panel.isVisible, state.service == service {
            panel.orderOut(nil)
            return
        }
        show(service)
    }

    func show(_ service: WebAssistantService) {
        state.service = service
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { position(panel) }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if let webView = webViews[service] { panel.makeFirstResponder(webView) }
    }

    /// Page web du service (créée et chargée à la première demande).
    func webView(for service: WebAssistantService) -> WKWebView {
        if let existing = webViews[service] { return existing }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Certains services (connexion Google) refusent les navigateurs intégrés inconnus :
        // on se présente comme Safari, qui utilise le même moteur WebKit.
        webView.customUserAgent = Self.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: service.url))
        webViews[service] = webView
        return webView
    }

    func reload() {
        webViews[state.service]?.reload()
    }

    func openInBrowser() {
        let url = webViews[state.service]?.url ?? state.service.url
        NSWorkspace.shared.open(url)
    }

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: Fenêtre

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 340, height: 420)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: WebAssistantContainer(controller: self, state: state))
        return panel
    }

    /// Centre la fenêtre sous l'encoche de l'écran où se trouve la souris.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 8))
    }

    private static var safariUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    }
}

/// Service affiché dans la fenêtre.
@MainActor
@Observable
final class WebAssistantState {
    var service: WebAssistantService = .chatGPT
}

/// Contenu de la fenêtre : barre de choix du service, puis la page.
private struct WebAssistantContainer: View {
    let controller: WebAssistantWindowController
    @Bindable var state: WebAssistantState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Service", selection: $state.service) {
                    ForEach(WebAssistantService.allCases) { service in
                        Text(service.title).tag(service)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer(minLength: 0)
                Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Recharger")
                Button { controller.openInBrowser() } label: { Image(systemName: "safari") }
                    .help("Ouvrir dans le navigateur")
            }
            .buttonStyle(.borderless)
            .padding(.leading, 78)  // place des boutons de fenêtre
            .padding(.trailing, 12)
            .frame(height: 38)

            WebViewHost(webView: controller.webView(for: state.service))
                .id(state.service)
        }
        .frame(minWidth: 340, minHeight: 420)
    }
}

/// Affiche une page `WKWebView` existante (non recréée quand on change de service).
private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
