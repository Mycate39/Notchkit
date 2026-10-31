#if DEBUG
import AVFoundation
import AppKit
import ScreenCaptureKit

/// Enregistre les fenêtres de Notchkit seules (encoche, grand lecteur de l'écran verrouillé), sur fond
/// transparent, en ProRes 4444 (avec couche alpha). Avec `backdrop`, le fond d'écran du bureau est filmé
/// derrière (image opaque) : le verre de macOS a alors exactement le rendu réel. La zone filmée est fixe
/// (haut de l'écran, centrée sur l'encoche) : la fenêtre peut changer de taille sans que l'image bouge.
/// Demande l'autorisation « Enregistrement de l'écran ».
@MainActor
final class DemoRecorder {
    enum RecorderError: Error { case windowNotFound, writerFailed(String) }

    private var stream: SCStream?
    private var output: DemoStreamOutput?

    /// Démarre l'enregistrement de `window` dans `region` (points, origine en haut à gauche de l'écran).
    func start(window: NSWindow, region: CGRect, scale: CGFloat, fps: Int, backdrop: Bool = false, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let app = content.applications.first(where: { $0.processID == pid }),
              let screenID = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == screenID })
        else { throw RecorderError.windowNotFound }

        // Toutes les fenêtres de l'app, même celles qui s'ouvrent pendant la prise. Avec le fond d'écran :
        // tout l'écran, moins les fenêtres des autres apps posées au-dessus de lui (icônes du bureau,
        // barre des menus, fenêtres ordinaires) ; le fond d'écran n'appartient pas au Dock sur macOS 27.
        let filter: SCContentFilter
        if backdrop {
            let desktop = Int(CGWindowLevelForKey(.desktopWindow))
            let above = content.windows.filter { $0.owningApplication?.processID != pid && $0.windowLayer > desktop }
            filter = SCContentFilter(display: display, excludingWindows: above)
        } else {
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.sourceRect = region
        config.width = Int(region.width * scale)
        config.height = Int(region.height * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.shouldBeOpaque = backdrop
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 8

        let output = try DemoStreamOutput(url: url, width: config.width, height: config.height)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
        self.output = output
        await output.waitForFirstFrame()
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        await output?.finish()
        output = nil
    }
}

/// Reçoit les images de ScreenCaptureKit et les écrit dans le fichier (file d'attente dédiée).
private final class DemoStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "notchkit.demo.recorder")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var firstFrame: CheckedContinuation<Void, Never>?
    private var gotFirstFrame = false

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func waitForFirstFrame() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.gotFirstFrame { continuation.resume() } else { self.firstFrame = continuation }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, isComplete(buffer) else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
        if !gotFirstFrame {
            gotFirstFrame = true
            firstFrame?.resume()
            firstFrame = nil
        }
    }

    /// Image entière (pas une image « inchangée » sans contenu).
    private func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard self.started else { return continuation.resume() }
                self.input.markAsFinished()
                self.writer.finishWriting { continuation.resume() }
            }
        }
    }
}
#endif
