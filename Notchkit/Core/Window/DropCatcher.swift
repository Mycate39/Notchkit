import AppKit

/// Fenêtre invisible qui reçoit les fichiers glissés sur l'encoche.
///
/// L'encoche vit dans un espace SkyLight au-dessus des bureaux (`LockScreenSpace`) : le serveur de
/// fenêtres ne lui livre plus le glisser-déposer. Cette fenêtre, dans les bureaux ordinaires, occupe
/// exactement le même cadre que l'encoche et transmet chaque étape du glisser à la vue de l'encoche
/// (mêmes coordonnées, donc mêmes zones de dépôt). Elle laisse passer la souris, sauf pendant le
/// glisser d'un fichier ou d'un texte, détecté par le presse-papiers de glisser (`NSPasteboard.drag`).
@MainActor
final class DropCatcher {
    private let panel: NSPanel
    private let view: DropCatcherView
    private var monitor: Any?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var releaseTask: Task<Void, Never>?
    /// Début et fin d'un glisser de fichier : le contenu de l'encoche passe dans cette fenêtre, ordinaire,
    /// pour que l'image du fichier glissé s'affiche au-dessus (l'espace SkyLight passerait devant).
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    private var isDragging = false

    init(forwardingTo target: NSView) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Presque transparente : une fenêtre entièrement transparente laisserait aussi filer le glisser.
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.002)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        view = DropCatcherView(target: target)
        panel.contentView = view
    }

    /// Affiche la fenêtre (sous l'encoche) et commence à guetter les glissers de fichiers.
    func start(frame: NSRect) {
        follow(frame)
        panel.orderFrontRegardless()
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            MainActor.assumeIsolated { [weak self] in self?.dragMoved() }
        }
    }

    /// Accueille le contenu de l'encoche pendant un glisser (même cadre : rien ne bouge à l'écran).
    func host(_ content: NSView) {
        content.frame = view.bounds
        content.autoresizingMask = [.width, .height]
        view.addSubview(content)
    }

    func follow(_ frame: NSRect) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
    }

    /// Nouveau contenu dans le presse-papiers de glisser = un glisser commence dans une autre app.
    private func dragMoved() {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount else { return }
        dragChangeCount = pasteboard.changeCount
        guard Self.isDroppable(pasteboard.types ?? []) else { return }
        panel.ignoresMouseEvents = false
        if !isDragging {
            isDragging = true
            onDragStart()
        }
        watchRelease()
    }

    /// Types acceptés par l'encoche : fichiers et texte (fonction pure, testée).
    nonisolated static func isDroppable(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(.fileURL) || types.contains(.string)
    }

    /// Bouton relâché : la fenêtre laisse de nouveau passer la souris (après le dépôt).
    private func watchRelease() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(150))
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.panel.ignoresMouseEvents = true
            if self.isDragging {
                self.isDragging = false
                self.onDragEnd()
            }
        }
    }
}

/// Vue de la fenêtre de réception : transmet le glisser-déposer à la vue de l'encoche.
private final class DropCatcherView: NSView {
    private weak var target: NSView?

    init(target: NSView) {
        self.target = target
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) indisponible") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropLog.notice("glisser reçu par la fenêtre de réception")
        return target?.draggingEntered(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        target?.draggingUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        target?.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        target?.draggingEnded(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target?.prepareForDragOperation(sender) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target?.performDragOperation(sender) ?? false
    }
}
