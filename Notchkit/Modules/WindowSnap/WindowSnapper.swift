import AppKit
import ApplicationServices
import SwiftUI

/// Disposition du panneau de zones (pure, testée) : tuiles en rangées, sous l'encoche.
enum SnapLayout {
    static let tile = CGSize(width: 60, height: 40)
    static let gap: CGFloat = 8
    static let padding: CGFloat = 10
    /// Distance entre le haut de l'écran et le haut du panneau (sous la barre des menus et l'encoche).
    static let topOffset: CGFloat = 44

    static var panelSize: CGSize {
        let columns = CGFloat(SnapZone.rows.map(\.count).max() ?? 0)
        let rows = CGFloat(SnapZone.rows.count)
        return CGSize(width: padding * 2 + columns * tile.width + (columns - 1) * gap,
                      height: padding * 2 + rows * tile.height + (rows - 1) * gap)
    }

    /// Cadre du panneau (coordonnées AppKit), centré en haut de l'écran.
    static func panelFrame(screen: CGRect) -> CGRect {
        let size = panelSize
        return CGRect(x: screen.midX - size.width / 2, y: screen.maxY - topOffset - size.height,
                      width: size.width, height: size.height)
    }

    /// Cadre de chaque tuile (coordonnées AppKit, origine en bas à gauche).
    static func tileFrames(panel: CGRect) -> [SnapZone: CGRect] {
        var frames: [SnapZone: CGRect] = [:]
        for (row, zones) in SnapZone.rows.enumerated() {
            for (column, zone) in zones.enumerated() {
                let x = panel.minX + padding + CGFloat(column) * (tile.width + gap)
                let top = panel.maxY - padding - CGFloat(row) * (tile.height + gap)
                frames[zone] = CGRect(x: x, y: top - tile.height, width: tile.width, height: tile.height)
            }
        }
        return frames
    }

    static func zone(at point: CGPoint, panel: CGRect) -> SnapZone? {
        tileFrames(panel: panel).first { $0.value.insetBy(dx: -gap / 2, dy: -gap / 2).contains(point) }?.key
    }
}

/// Repère la fenêtre déplacée (souris, accessibilité) et propose les zones quand elle approche du haut
/// de l'écran. Les moniteurs globaux de souris ne lisent que la position, jamais le contenu.
@MainActor
final class WindowSnapper {
    private var monitors: [Any] = []
    private var window: AXUIElement?
    private var startPosition: CGPoint?
    private var isMovingWindow = false
    private var lastCheck = Date.distantPast
    private let panel = SnapPanel()

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] _ in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() }),
        ]
        for (mask, handler) in handlers {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
                MainActor.assumeIsolated { handler(event) }
            }) {
                monitors.append(monitor)
            }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    // MARK: Souris

    private func mouseDown() {
        reset()
        guard AXIsProcessTrusted() else { return }
        let point = Self.axPoint(NSEvent.mouseLocation)
        guard let window = Self.window(at: point), let position = Self.position(of: window) else { return }
        self.window = window
        startPosition = position
    }

    private func mouseDragged() {
        guard let window, let startPosition else { return }
        if !isMovingWindow {
            // La fenêtre bouge-t-elle ? (vérifié au plus toutes les 50 ms)
            guard Date().timeIntervalSince(lastCheck) > 0.05 else { return }
            lastCheck = Date()
            guard let position = Self.position(of: window), hypot(position.x - startPosition.x, position.y - startPosition.y) > 4
            else { return }
            isMovingWindow = true
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else { return }
        let panelFrame = SnapLayout.panelFrame(screen: screen.frame)
        let visible = SnapZone.isNearTop(pointerY: pointer.y, screenMaxY: screen.frame.maxY)
            || (panel.isVisible && panelFrame.insetBy(dx: -30, dy: -30).contains(pointer))
        if visible {
            panel.show(frame: panelFrame, hovered: SnapLayout.zone(at: pointer, panel: panelFrame))
        } else {
            panel.hide()
        }
    }

    private func mouseUp() {
        defer { reset() }
        guard isMovingWindow, panel.isVisible, let window else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              let zone = SnapLayout.zone(at: pointer, panel: SnapLayout.panelFrame(screen: screen.frame))
        else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let target = zone.frame(visibleFrame: screen.visibleFrame, primaryHeight: primaryHeight)
        // La fenêtre est encore « tenue » par la souris : on la place juste après le relâchement.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.setFrame(target, of: window)
        }
        Haptics.play(.snap)
    }

    private func reset() {
        window = nil
        startPosition = nil
        isMovingWindow = false
        panel.hide()
    }

    // MARK: Accessibilité

    /// Point AppKit (origine en bas) → point d'accessibilité (origine en haut de l'écran principal).
    static func axPoint(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }
        for _ in 0..<20 {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if role as? String == kAXWindowRole as String { return current }
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                return (window as! AXUIElement)
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        // Position, taille, puis position à nouveau : certaines apps ajustent la position en changeant de taille.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }
}

/// Panneau translucide des zones, affiché sous l'encoche pendant le déplacement d'une fenêtre.
@MainActor
final class SnapPanel {
    private let window: NSPanel
    private let model = SnapPanelModel()

    var isVisible: Bool { window.isVisible }

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: SnapZonesView(model: model))
    }

    func show(frame: CGRect, hovered: SnapZone?) {
        if model.hovered != hovered {
            if hovered != nil { Haptics.play(.tap) }
            withAnimation(.snappy(duration: 0.15)) { model.hovered = hovered }
        }
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible {
            model.isShown = false
            window.orderFrontRegardless()
            withAnimation(.spring(duration: 0.3, bounce: 0.25)) { model.isShown = true }
        }
    }

    func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        model.hovered = nil
    }
}

@MainActor
@Observable
final class SnapPanelModel {
    var hovered: SnapZone?
    var isShown = false
}

struct SnapZonesView: View {
    let model: SnapPanelModel

    var body: some View {
        VStack(spacing: SnapLayout.gap) {
            ForEach(Array(SnapZone.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: SnapLayout.gap) {
                    ForEach(row) { zone in
                        SnapTile(zone: zone, isHovered: model.hovered == zone)
                    }
                }
            }
        }
        .padding(SnapLayout.padding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .environment(\.colorScheme, .dark)
        .scaleEffect(model.isShown ? 1 : 0.9, anchor: .top)
        .opacity(model.isShown ? 1 : 0)
    }
}

/// Mini-écran avec la zone mise en valeur.
private struct SnapTile: View {
    let zone: SnapZone
    let isHovered: Bool

    var body: some View {
        GeometryReader { proxy in
            let unit = zone.unitRect
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.18 : 0.08))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(StandBy.amber) : AnyShapeStyle(.white.opacity(0.55)))
                    .frame(width: max(4, unit.width * (proxy.size.width - 6) - 2),
                           height: max(4, unit.height * (proxy.size.height - 6) - 2))
                    .offset(x: 3 + unit.minX * (proxy.size.width - 6) + 1, y: 3 + unit.minY * (proxy.size.height - 6) + 1)
            }
        }
        .frame(width: SnapLayout.tile.width, height: SnapLayout.tile.height)
        .scaleEffect(isHovered ? 1.08 : 1)
    }
}
