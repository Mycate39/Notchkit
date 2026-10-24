import CoreMedia
import Foundation
import ScreenCaptureKit

/// Compte les images que l'app au premier plan affiche réellement : ScreenCaptureKit ne livre une
/// image « complète » que quand le contenu a changé (les autres sont marquées inactives).
/// Capture minuscule (64 × 36), jamais enregistrée ; nécessite l'autorisation Enregistrement de l'écran.
final class FrameRateMeter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.andeolchenaux.notchkit.fps")
    private var frameTimes: [TimeInterval] = []
    private var stream: SCStream?
    /// Augmente à chaque arrêt : une capture lancée entre-temps est abandonnée.
    private var generation = 0

    /// Images affichées pendant la dernière seconde (fonction pure, testée).
    static func fps(frameTimes: [TimeInterval], now: TimeInterval) -> Int {
        frameTimes.filter { $0 > now - 1 && $0 <= now }.count
    }

    var currentFPS: Int {
        lock.withLock { Self.fps(frameTimes: frameTimes, now: ProcessInfo.processInfo.systemUptime) }
    }

    /// Mesure l'app `pid` sur l'écran qui porte sa plus grande fenêtre.
    func start(pid: pid_t) async throws {
        stop()
        let token = lock.withLock { generation }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let app = content.applications.first(where: { $0.processID == pid }) else { return }
        let largest = content.windows
            .filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let display = largest.flatMap { window in content.displays.first { $0.frame.intersects(window.frame) } }
            ?? content.displays.first
        guard let display else { return }

        let config = SCStreamConfiguration()
        config.width = 64
        config.height = 36
        config.minimumFrameInterval = CMTime(value: 1, timescale: 240)
        config.queueDepth = 3
        config.showsCursor = false
        let stream = SCStream(filter: SCContentFilter(display: display, including: [app], exceptingWindows: []),
                              configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        let current = lock.withLock {
            guard generation == token else { return false }
            self.stream = stream
            return true
        }
        if !current { try? await stream.stopCapture() }
    }

    func stop() {
        let old = lock.withLock {
            generation += 1
            frameTimes = []
            defer { stream = nil }
            return stream
        }
        if let old { old.stopCapture { _ in } }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            frameTimes.append(now)
            if let first = frameTimes.first, first < now - 2 { frameTimes.removeAll { $0 < now - 1 } }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock {
            if self.stream === stream { self.stream = nil }
            frameTimes = []
        }
    }
}

/// Plein écran, comme le mode jeu de macOS : une fenêtre de l'app couvre tout un écran
/// (sous l'encoche pour une app qui ne l'utilise pas, d'où la marge en haut).
enum FullScreenDetector {
    /// Hauteur de l'encoche laissée libre par une app plein écran qui ne l'utilise pas.
    static let notchAllowance: CGFloat = 40

    /// Rectangles en coordonnées globales, origine en haut à gauche (fonction pure, testée).
    static func isFullScreen(windows: [CGRect], displays: [CGRect]) -> Bool {
        windows.contains { window in
            displays.contains { display in
                window.minX <= display.minX + 1 && window.maxX >= display.maxX - 1
                    && window.maxY >= display.maxY - 1 && window.minY <= display.minY + notchAllowance
            }
        }
    }

    /// `display` : seulement cet écran (cadre en coordonnées globales, origine en haut à gauche),
    /// sinon n'importe lequel.
    static func isFullScreen(pid: pid_t, display: CGRect? = nil) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let windows = info.compactMap { entry -> CGRect? in
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        guard !windows.isEmpty else { return false }
        if let display { return isFullScreen(windows: windows, displays: [display]) }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return isFullScreen(windows: windows, displays: ids.prefix(Int(count)).map(CGDisplayBounds))
    }
}
